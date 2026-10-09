import FirebaseFirestore

/// The in-app inbox. The `notify` Cloud Function writes these; the app only reads them and marks them read.
struct NotificationRepository {
    let db: Firestore
    var notifications: CollectionReference { db.collection("notifications") }

    func watch(_ uid: String) -> AsyncThrowingStream<[AppNotification], Error> {
        notifications.whereField("userId", isEqualTo: uid).order(by: "createdAt", descending: true).limit(to: 50)
            .streamList { try? $0.data(as: AppNotification.self) }
    }

    func markRead(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let b = db.batch()
        for id in ids { b.updateData(["read": true], forDocument: notifications.document(id)) }
        try await b.commit()
    }
}
