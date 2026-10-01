import SwiftUI
import FirebaseAuth

@MainActor @Observable
final class SessionStore {
    private(set) var uid: String?
    private(set) var profile: UserProfile?
    private(set) var player: PlayerProfile?
    private(set) var loading = true
    var isSignedIn: Bool { profile != nil }

    private let users: UserRepository
    private let players: PlayerRepository
    private var handle: AuthStateDidChangeListenerHandle?
    private var tasks: [Task<Void, Never>] = []

    init(users: UserRepository, players: PlayerRepository) {
        self.users = users
        self.players = players
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.userChanged(user?.uid) }
        }
        NotificationService.shared.onToken = { [weak self] token in
            guard let self, let uid = self.uid else { return }
            Task { try? await users.addFCMToken(uid, token) }
        }
    }

    private func userChanged(_ uid: String?) {
        guard uid != self.uid || loading else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
        self.uid = uid
        profile = nil
        player = nil
        guard let uid else { loading = false; return }
        loading = true

        tasks.append(Task { [users] in
            do {
                for try await p in users.watch(uid) {
                    self.profile = p?.createdAt.isEmpty == false ? p : nil
                    self.loading = false
                }
            } catch { self.loading = false }
        })
        tasks.append(Task { [players] in
            do { for try await p in players.watch(uid) { self.player = p } } catch {}
        })
        if let token = NotificationService.shared.latestToken {
            tasks.append(Task { [users] in try? await users.addFCMToken(uid, token) })
        }
    }

    func updateName(_ name: String) {
        guard var p = profile else { return }
        p.name = name.trimmingCharacters(in: .whitespaces)
        try? users.save(p)
    }

    func signOut() { try? Auth.auth().signOut() }
}
