import FirebaseFirestore

/// Home hero banners, managed in the Firebase console: `imageUrl`, optional `linkUrl`, and `order`.
struct BannerRepository {
    let db: Firestore

    func watch() -> AsyncThrowingStream<[Banner], Error> {
        db.collection("banners").order(by: "order").streamList { doc in
            guard var banner = try? doc.data(as: Banner.self) else { return nil }
            banner.id = doc.documentID
            return banner
        }
    }
}
