import FirebaseFirestore

struct TeamRepository {
    let db: Firestore
    var teams: CollectionReference { db.collection("teams") }
    var members: CollectionReference { db.collection("teamMembers") }

    func watchTeam(_ id: String) -> AsyncThrowingStream<Team?, Error> { teams.document(id).stream(Team.self) }
    func watchMembers(team id: String) -> AsyncThrowingStream<[TeamMember], Error> { watch(members.whereField("teamId", isEqualTo: id)) }
    func watchMemberships(player id: String) -> AsyncThrowingStream<[TeamMember], Error> { watch(members.whereField("playerId", isEqualTo: id)) }
    func watchSentInvites(owner id: String) -> AsyncThrowingStream<[TeamMember], Error> { watch(members.whereField("ownerId", isEqualTo: id)) }

    private func watch(_ q: Query) -> AsyncThrowingStream<[TeamMember], Error> {
        q.streamList(sorted: { $0.invitedAt < $1.invitedAt }) { try? $0.data(as: TeamMember.self) }
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

    /// Waits for the server, so the `notify` call that follows can read the invite.
    func invite(_ m: TeamMember) async throws { try await members.document(m.id).setData(Firestore.Encoder().encode(m)) }

    func accept(_ m: TeamMember) async throws {
        try await members.document(m.id).updateData(["status": "accepted", "respondedAt": ISODate.string(.now)])
    }

    func decline(_ m: TeamMember, reason: String) async throws {
        var data: [String: Any] = ["status": "declined", "respondedAt": ISODate.string(.now)]
        if !reason.trimmed.isEmpty { data["declineReason"] = reason.trimmed }
        try await members.document(m.id).updateData(data)
    }

    func remove(_ m: TeamMember) async throws { try await members.document(m.id).delete() }

    func setCaptains(_ teamID: String, captain: String?, vice: String?) async throws {
        try await teams.document(teamID).updateData([
            "captainId": captain ?? FieldValue.delete(),
            "viceCaptainId": vice ?? FieldValue.delete(),
        ])
    }

    func setLogo(_ teamID: String, url: String) async throws {
        let b = db.batch()
        b.updateData(["logoUrl": url], forDocument: teams.document(teamID))
        for d in try await members.whereField("teamId", isEqualTo: teamID).getDocuments().documents {
            b.updateData(["teamLogoUrl": url], forDocument: d.reference)
        }
        try await b.commit()
    }
}
