import SwiftUI

/// The signed-in user's notifications, kept live for the bell badge and the notifications screen.
@MainActor @Observable
final class InboxStore {
    private(set) var notifications: [AppNotification]?
    var unreadCount: Int { notifications?.filter { !$0.read }.count ?? 0 }

    private let repo: NotificationRepository

    init(repo: NotificationRepository) { self.repo = repo }

    func watch(uid: String?) async {
        notifications = nil
        guard let uid else { return }
        do {
            for try await n in repo.watch(uid) { notifications = n }
        } catch {
            notifications = []
        }
    }

    func markRead(_ n: AppNotification) async {
        guard !n.read else { return }
        try? await repo.markRead([n.id])
    }

    func markAllRead() async {
        try? await repo.markRead(notifications?.filter { !$0.read }.map(\.id) ?? [])
    }
}

#if DEBUG
extension InboxStore {
    func preview(_ items: [AppNotification]?) { notifications = items }
}
#endif
