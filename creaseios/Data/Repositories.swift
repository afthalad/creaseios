import FirebaseFirestore
import CreaseEngine

struct MatchRepository {
    let db: Firestore
    var matches: CollectionReference { db.collection("matches") }
    func events(_ id: String) -> CollectionReference { matches.document(id).collection("events") }

    /// Public matches, mine, and ones waiting on my confirmation, newest first.
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
        return base.order(by: "createdAt", descending: true).stream { snap in
            snap.documents.compactMap { try? $0.match() }.filter { $0.isVisible(to: uid) }
        }
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

    func watchEvents(_ id: String) -> AsyncThrowingStream<[MatchEvent], Error> {
        events(id).order(by: "seq").stream { $0.documents.compactMap { try? $0.data(as: MatchEvent.self) } }
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

struct UserRepository {
    let db: Firestore
    func doc(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }

    func watch(_ uid: String) -> AsyncThrowingStream<UserProfile?, Error> { doc(uid).stream(UserProfile.self) }

    func get(_ uid: String) async throws -> UserProfile? {
        let s = try await doc(uid).getDocument()
        return s.data()?["createdAt"] == nil ? nil : try s.data(as: UserProfile.self)
    }

    func save(_ p: UserProfile) throws { try doc(p.uid).setData(from: p, merge: true) }

    func setFavorite(_ uid: String, _ matchID: String, _ on: Bool) async throws {
        try await toggle("favoriteMatchIds", uid, matchID, on)
    }

    func setReminder(_ uid: String, _ matchID: String, _ on: Bool) async throws {
        try await toggle("reminderMatchIds", uid, matchID, on)
    }

    func addFCMToken(_ uid: String, _ token: String) async throws {
        try await doc(uid).setData(["fcmTokens": FieldValue.arrayUnion([token])], merge: true)
    }

    private func toggle(_ field: String, _ uid: String, _ value: String, _ on: Bool) async throws {
        let op = on ? FieldValue.arrayUnion([value]) : FieldValue.arrayRemove([value])
        try await doc(uid).setData([field: op], merge: true)
    }
}

struct PlayerRepository {
    let db: Firestore
    let functions: EdgeFunctions
    var players: CollectionReference { db.collection("players") }

    func watch(_ uid: String) -> AsyncThrowingStream<PlayerProfile?, Error> { players.document(uid).stream(PlayerProfile.self) }

    func save(_ p: PlayerProfile, photo: Data? = nil) async throws {
        var p = p
        if let photo { p.photoUrl = try await functions.uploadPhoto(photo) }
        p.searchTokens = searchTokens(p.name)
        try players.document(p.uid).setData(from: p)
    }

    func search(_ query: String) async throws -> [PlayerProfile] {
        let term = query.trimmed.lowercased()
        guard !term.isEmpty else { return [] }
        return try await players.whereField("searchTokens", arrayContains: term).limit(to: 20)
            .getDocuments().documents.compactMap { try? $0.data(as: PlayerProfile.self) }
    }
}

struct TeamRepository {
    let db: Firestore
    var teams: CollectionReference { db.collection("teams") }
    var members: CollectionReference { db.collection("teamMembers") }

    func watchTeam(_ id: String) -> AsyncThrowingStream<Team?, Error> { teams.document(id).stream(Team.self) }
    func watchMembers(team id: String) -> AsyncThrowingStream<[TeamMember], Error> { watch(members.whereField("teamId", isEqualTo: id)) }
    func watchMemberships(player id: String) -> AsyncThrowingStream<[TeamMember], Error> { watch(members.whereField("playerId", isEqualTo: id)) }

    private func watch(_ q: Query) -> AsyncThrowingStream<[TeamMember], Error> {
        q.stream { $0.documents.compactMap { try? $0.data(as: TeamMember.self) }.sorted { $0.invitedAt < $1.invitedAt } }
    }

    func search(_ query: String) async throws -> [Team] {
        let term = query.trimmed.lowercased()
        guard !term.isEmpty else { return [] }
        return try await teams.whereField("searchTokens", arrayContains: term).limit(to: 20)
            .getDocuments().documents.compactMap { try? $0.data(as: Team.self) }
    }

    func ownedBy(_ uid: String) async throws -> [Team] {
        try await teams.whereField("ownerId", isEqualTo: uid).getDocuments().documents.compactMap { try? $0.data(as: Team.self) }
    }

    func acceptedMembers(_ teamID: String) async throws -> [TeamMember] {
        try await members.whereField("teamId", isEqualTo: teamID).whereField("status", isEqualTo: "accepted")
            .getDocuments().documents.compactMap { try? $0.data(as: TeamMember.self) }.sorted { $0.invitedAt < $1.invitedAt }
    }

    /// One batch: the teamMembers rule reads the new team with getAfter().
    func create(_ team: Team, owner: TeamMember) async throws {
        let b = db.batch()
        try b.setData(from: team, forDocument: teams.document(team.id))
        try b.setData(from: owner, forDocument: members.document(owner.id))
        try await b.commit()
    }

    func invite(_ m: TeamMember) throws { try members.document(m.id).setData(from: m) }
    func accept(_ m: TeamMember) async throws { try await members.document(m.id).updateData(["status": "accepted"]) }
    func remove(_ m: TeamMember) async throws { try await members.document(m.id).delete() }

    func setLogo(_ teamID: String, url: String) async throws {
        let b = db.batch()
        b.updateData(["logoUrl": url], forDocument: teams.document(teamID))
        for d in try await members.whereField("teamId", isEqualTo: teamID).getDocuments().documents {
            b.updateData(["teamLogoUrl": url], forDocument: d.reference)
        }
        try await b.commit()
    }
}
