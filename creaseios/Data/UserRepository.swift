import FirebaseFirestore

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
