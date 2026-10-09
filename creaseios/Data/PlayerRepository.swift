import FirebaseFirestore

struct PlayerRepository {
    let db: Firestore
    let photos: PhotoStorage
    var players: CollectionReference { db.collection("players") }

    func watch(_ uid: String) -> AsyncThrowingStream<PlayerProfile?, Error> { players.document(uid).stream(PlayerProfile.self) }
    func get(_ uid: String) async throws -> PlayerProfile? { try? await players.document(uid).getDocument(as: PlayerProfile.self) }

    func save(_ p: PlayerProfile, photo: Data? = nil) async throws {
        var p = p
        if let photo { p.photoUrl = try await photos.upload(photo) }
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
