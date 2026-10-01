import SwiftUI
import FirebaseFirestore
import CreaseEngine

enum AppConfig {
    static let functionsBaseURL = URL(string: "https://zopovxkefvavxxlhnwzs.supabase.co/functions/v1")!
}

@MainActor @Observable
final class AppEnvironment {
    let engine = CreaseEngine()
    let functions = EdgeFunctions(baseURL: AppConfig.functionsBaseURL)
    let matches: MatchRepository
    let users: UserRepository
    let players: PlayerRepository
    let teams: TeamRepository

    let router = Router()
    let settings = SettingsStore()
    let session: SessionStore

    init() {
        let db = Firestore.firestore()
        matches = MatchRepository(db: db)
        users = UserRepository(db: db)
        players = PlayerRepository(db: db, functions: functions)
        teams = TeamRepository(db: db)
        session = SessionStore(users: users, players: players)

        NotificationService.shared.onOpenRoute = { [router] path in router.open(path: path) }
        NotificationService.shared.flushPendingRoute()
    }
}
