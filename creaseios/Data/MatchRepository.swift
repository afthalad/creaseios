import FirebaseFirestore

struct MatchRepository {
    let db: Firestore
    var matches: CollectionReference { db.collection("matches") }
    func events(_ id: String) -> CollectionReference { matches.document(id).collection("events") }

    /// Public matches, mine, and ones waiting on my confirmation: the newest 100.
    func watchMatches(uid: String?) -> AsyncThrowingStream<[Match], Error> {
        let base: Query
        if let uid {
            base = matches.whereFilter(.orFilter([
                .whereField("isPublic", isEqualTo: true),
                .whereField("createdBy", isEqualTo: uid),
                .whereField("pendingOwnerIds", arrayContains: uid),
            ]))
        } else {
            base = matches.whereField("isPublic", isEqualTo: true)
        }
        return base.order(by: "createdAt", descending: true).limit(to: 100)
            .streamList { doc in (try? doc.match()).flatMap { $0.isVisible(to: uid) ? $0 : nil } }
    }

    func watchMatch(_ id: String) -> AsyncThrowingStream<Match?, Error> {
        matches.document(id).stream { try $0.match() }
    }

    func getMatch(_ id: String) async throws -> Match? {
        let s = try await matches.document(id).getDocument()
        return s.exists ? try s.match() : nil
    }

    func create(_ m: Match) throws { try matches.document(m.id).setData(from: m) }
    func update(_ m: Match) throws { try matches.document(m.id).setData(from: m, merge: true) }

    func loadEvents(_ id: String, afterSeq: Int? = nil) async throws -> [MatchEvent] {
        var q: Query = events(id).order(by: "seq")
        if let afterSeq { q = q.whereField("seq", isGreaterThan: afterSeq) }
        return try await q.getDocuments().documents.compactMap { try? $0.data(as: MatchEvent.self) }
    }

    /// Matches either side of which was picked from this team. Rules aren't filters, so each query is
    /// limited to public matches or the viewer's own.
    func teamMatches(_ teamID: String, uid: String?) async throws -> [Match] {
        var queries: [Query] = []
        for side in ["teamA.teamId", "teamB.teamId"] {
            queries.append(matches.whereField(side, isEqualTo: teamID).whereField("isPublic", isEqualTo: true))
            if let uid { queries.append(matches.whereField(side, isEqualTo: teamID).whereField("createdBy", isEqualTo: uid)) }
        }
        return try await withThrowingTaskGroup(of: [Match].self) { group in
            for q in queries {
                group.addTask { try await q.getDocuments().documents.compactMap { try? $0.match() } }
            }
            var byID: [String: Match] = [:]
            for try await list in group { for m in list { byID[m.id] = m } }
            return Array(byID.values)
        }
    }

    func watchEvents(_ id: String) -> AsyncThrowingStream<[MatchEvent], Error> {
        events(id).order(by: "seq").streamList { try? $0.data(as: MatchEvent.self) }
    }

    /// Writes to the local cache immediately and syncs in the background, so scoring works offline.
    func append(_ id: String, _ e: MatchEvent) throws {
        try events(id).document("\(e.seq)").setData(from: e)
    }

    func confirm(_ id: String, status: MatchStatus, pendingOwnerIds: [String]) async throws {
        try await matches.document(id).updateData(["status": status.rawValue, "pendingOwnerIds": pendingOwnerIds])
    }

    func delete(_ id: String) async throws {
        let batch = db.batch()
        for d in try await events(id).getDocuments().documents { batch.deleteDocument(d.reference) }
        batch.deleteDocument(matches.document(id))
        try await batch.commit()
    }
}
