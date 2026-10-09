import SwiftUI
import FirebaseFirestore

@MainActor @Observable
final class AppEnvironment {
    let engine = CreaseEngine()
    let photos = PhotoStorage()
    let notifier = Notifier()
    let matches: MatchRepository
    let users: UserRepository
    let players: PlayerRepository
    let teams: TeamRepository
    let banners: BannerRepository
    let inbox: InboxStore

    let router = Router()
    let settings = SettingsStore()
    let session: SessionStore

    init() {
        let db = Firestore.firestore()
        matches = MatchRepository(db: db)
        users = UserRepository(db: db)
        players = PlayerRepository(db: db, photos: photos)
        teams = TeamRepository(db: db)
        banners = BannerRepository(db: db)
        inbox = InboxStore(repo: NotificationRepository(db: db))
        session = SessionStore(users: users, players: players)

        NotificationService.shared.onOpenRoute = { [router] path in router.open(path: path) }
        NotificationService.shared.flushPendingRoute()
    }
}
