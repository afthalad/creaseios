import SwiftUI

struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router

    var body: some View {
        let inbox = env.inbox
        ScrollView {
            LazyVStack(spacing: 10) {
                if let items = inbox.notifications {
                    if items.isEmpty { MessageView(text: "notificationsEmpty", systemImage: "bell") }
                    ForEach(items) { n in
                        Button { open(n) } label: { NotificationRow(notification: n) }.buttonStyle(.plain)
                    }
                } else {
                    ForEach(0..<4, id: \.self) { _ in Skeleton(height: 84, radius: 18) }
                }
            }
            .padding(16)
            .smoothChange(inbox.notifications)
        }
        .screenBackground()
        .brandTitle("notificationsTitle")
        .clearNavBar()
        .toolbar {
            if inbox.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("markAllRead") { Task { await inbox.markAllRead() } }
                        .font(AppFont.body(14, .semibold))
                        .foregroundStyle(Palette.btn)
                }
                .withoutGlass()
            }
        }
    }

    private func open(_ n: AppNotification) {
        Task { await env.inbox.markRead(n) }
        switch n.kind {
        case .teamInvite: router.push(.invites)
        case .inviteAccepted, .inviteDeclined: router.push(.team(id: n.teamId))
        }
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    @Environment(\.locale) private var locale

    private var n: AppNotification { notification }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TeamBadge(shortName: shortName(n.teamName), color: Palette.brand2, logoURL: n.teamLogoUrl, size: 44, circular: true)
                .overlay(alignment: .bottomTrailing) { kindIcon.offset(x: 4, y: 4) }
            VStack(alignment: .leading, spacing: 6) {
                message.font(AppFont.body(14.5)).foregroundStyle(Palette.ink)
                if let reason = n.reason, !reason.isEmpty { DeclineReason(reason: reason) }
                Text(verbatim: n.createdDate.formatted(.relative(presentation: .named).locale(locale)))
                    .font(AppFont.body(12))
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
            if !n.read {
                Circle().fill(Palette.live).frame(width: 8, height: 8).padding(.top, 6)
            }
        }
        .card()
    }

    private var message: Text {
        switch n.kind {
        case .teamInvite: Text("notifTeamInvite \(n.fromName) \(n.teamName)")
        case .inviteAccepted: Text("notifInviteAccepted \(n.fromName) \(n.teamName)")
        case .inviteDeclined: Text("notifInviteDeclined \(n.fromName) \(n.teamName)")
        }
    }

    private var kindIcon: some View {
        let (icon, color): (String, Color) = switch n.kind {
        case .teamInvite: ("envelope.fill", Palette.four)
        case .inviteAccepted: ("checkmark", Palette.six)
        case .inviteDeclined: ("xmark", Palette.wicket)
        }
        return Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(color))
            .overlay(Circle().stroke(Palette.surface, lineWidth: 2))
    }
}

#if DEBUG
#Preview("Notifications") {
    NavigationStack { NotificationsView() }.previewEnvironment()
}

#Preview("Notifications empty") {
    let env = AppEnvironment.preview()
    env.inbox.preview([])
    return NavigationStack { NotificationsView() }.previewEnvironment(env)
}

#Preview("Notification rows") {
    VStack(spacing: 10) {
        ForEach(AppNotification.samples) { NotificationRow(notification: $0) }
    }
    .padding()
    .screenBackground()
}
#endif
