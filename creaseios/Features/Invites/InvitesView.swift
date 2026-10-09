import SwiftUI

/// Each action returns false when the server rejects the write, so the screen can say so.
extension AppEnvironment {
    @discardableResult
    func sendInvite(_ invite: TeamMember) async -> Bool {
        do { try await teams.invite(invite) } catch { return false }
        await notifier.notify("team_invite", ["teamId": invite.teamId, "playerId": invite.playerId])
        return true
    }

    @discardableResult
    func accept(_ invite: TeamMember) async -> Bool {
        do { try await teams.accept(invite) } catch { return false }
        await notifier.notify("invite_accepted", ["teamId": invite.teamId, "playerId": invite.playerId])
        return true
    }

    @discardableResult
    func decline(_ invite: TeamMember, reason: String) async -> Bool {
        do { try await teams.decline(invite, reason: reason) } catch { return false }
        await notifier.notify("invite_declined", ["teamId": invite.teamId, "playerId": invite.playerId])
        return true
    }

    /// Sends a declined invite again as a fresh one.
    @discardableResult
    func inviteAgain(_ invite: TeamMember) async -> Bool {
        var m = invite
        m.status = .pending
        m.invitedAt = ISODate.string(.now)
        m.respondedAt = nil
        m.declineReason = nil
        return await sendInvite(m)
    }
}

@MainActor @Observable
final class InvitesModel {
    var received: [TeamMember]?
    var sent: [TeamMember]?
    let env: AppEnvironment

    init(env: AppEnvironment) { self.env = env }

    func watch(uid: String) async {
        async let r: Void = watchReceived(uid)
        async let s: Void = watchSent(uid)
        _ = await (r, s)
    }

    private func watchReceived(_ uid: String) async {
        do {
            for try await m in env.teams.watchMemberships(player: uid) { received = newestFirst(m) }
        } catch {
            received = []
        }
    }

    private func watchSent(_ uid: String) async {
        do {
            for try await m in env.teams.watchSentInvites(owner: uid) { sent = newestFirst(m) }
        } catch {
            sent = []
        }
    }

    /// Drops the owner's own membership, which was never an invite.
    private func newestFirst(_ list: [TeamMember]) -> [TeamMember] {
        list.filter { !$0.isOwner }.sorted { $0.invitedAt > $1.invitedAt }
    }
}

struct InvitesView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var model: InvitesModel?

    var body: some View {
        Group {
            if let model { InvitesContent(model: model) } else { SkeletonList(count: 3) }
        }
        .smoothChange(model == nil)
        .screenBackground()
        .brandTitle("invitesTitle")
        .clearNavBar()
        .task(id: session.uid) {
            guard let uid = session.uid else { return }
            let m = model ?? InvitesModel(env: env)
            model = m
            await m.watch(uid: uid)
        }
    }
}

private enum InvitesTab: Hashable { case received, sent }

private struct InvitesContent: View {
    let model: InvitesModel
    @State private var tab = InvitesTab.received
    @State private var declining: TeamMember?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            UnderlineTabs(tabs: [(.received, "invitesReceived"), (.sent, "invitesSent")], selection: $tab)
               
            ScrollView {
                LazyVStack(spacing: 10) {
                    switch tab {
                    case .received: received
                    case .sent: sent
                    }
                }
                .padding(16)
                .smoothChange(tab)
                .smoothChange(model.received)
                .smoothChange(model.sent)
            }
        }
        .sheet(item: $declining) { invite in
            DeclineInviteSheet(invite: invite) { reason in
                run { await model.env.decline(invite, reason: reason) }
            }
        }
        .alert("inviteActionFailed", isPresented: $failed) { Button("ok") {} }
    }

    private func run(_ action: @escaping () async -> Bool) {
        Task { await runNow(action) }
    }

    private func runNow(_ action: () async -> Bool) async {
        if await !action() { failed = true }
    }

    @ViewBuilder private var received: some View {
        if let list = model.received {
            if list.isEmpty { MessageView(text: "invitesReceivedEmpty", systemImage: "envelope.open") }
            ForEach(list) { invite in
                if invite.isPending {
                    InviteCard(invite: invite) {
                        await runNow { await model.env.accept(invite) }
                    } onDecline: {
                        declining = invite
                    }
                } else {
                    InviteRow(invite: invite, sent: false)
                }
            }
        } else {
            loading
        }
    }

    @ViewBuilder private var sent: some View {
        if let list = model.sent {
            if list.isEmpty { MessageView(text: "invitesSentEmpty", systemImage: "paperplane") }
            ForEach(list) { invite in
                InviteRow(invite: invite, sent: true) {
                    await runNow { await model.env.inviteAgain(invite) }
                }
                .contextMenu {
                    if invite.isPending {
                        Button(role: .destructive) { Task { try? await model.env.teams.remove(invite) } } label: {
                            Label("cancelInvite", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        } else {
            loading
        }
    }

    private var loading: some View {
        ForEach(0..<3, id: \.self) { _ in Skeleton(height: 84, radius: 18) }
    }
}

/// A pending invite to the signed-in player, with Accept and Decline.
struct InviteCard: View {
    let invite: TeamMember
    let onAccept: () async -> Void
    let onDecline: () -> Void
    @State private var accepting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TeamBadge(shortName: shortName(invite.teamName), color: Palette.brand2, logoURL: invite.teamLogoUrl, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: invite.teamName).font(AppFont.body(16, .semibold)).foregroundStyle(Palette.ink)
                    Text("teamInvitedBy \(invite.ownerName)").font(AppFont.body(13)).foregroundStyle(Palette.ink3)
                }
                Spacer()
                InviteTime(date: invite.invitedAt)
            }
            HStack(spacing: 10) {
                Button("decline", action: onDecline).secondaryButton()
                Button {
                    Task {
                        accepting = true
                        await onAccept()
                        accepting = false
                    }
                } label: {
                    if accepting { ProgressView().tint(Palette.onBrand) } else { Text("accept") }
                }
                .primaryButton()
            }
            .disabled(accepting)
        }
        .card()
    }
}

/// An invite and where it stands. Sent invites show the player; received ones show the team.
struct InviteRow: View {
    let invite: TeamMember
    let sent: Bool
    var onInviteAgain: (() async -> Void)? = nil
    @State private var inviting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if sent {
                    PlayerPhoto(photoURL: invite.playerPhotoUrl, gender: invite.playerGender, size: 44)
                } else {
                    TeamBadge(shortName: shortName(invite.teamName), color: Palette.brand2, logoURL: invite.teamLogoUrl, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sent ? invite.playerName : invite.teamName)
                        .font(AppFont.body(16, .semibold))
                        .foregroundStyle(Palette.ink)
                    Group {
                        if sent { Text(verbatim: invite.teamName) } else { Text("teamInvitedBy \(invite.ownerName)") }
                    }
                    .font(AppFont.body(13))
                    .foregroundStyle(Palette.ink3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    InviteStatusTag(status: invite.status)
                    InviteTime(date: invite.respondedAt ?? invite.invitedAt)
                }
            }
            if let reason = invite.declineReason, invite.status == .declined {
                DeclineReason(reason: reason)
            }
            if sent, invite.status == .declined, let onInviteAgain {
                Button {
                    Task {
                        inviting = true
                        await onInviteAgain()
                        inviting = false
                    }
                } label: {
                    if inviting { ProgressView() } else { Text("inviteAgain") }
                }
                .secondaryButton()
                .disabled(inviting)
            }
        }
        .card()
    }
}

struct InviteStatusTag: View {
    let status: MemberStatus

    var body: some View {
        let (key, color): (LocalizedStringKey, Color) = switch status {
        case .pending: ("memberPending", Palette.extra)
        case .accepted: ("inviteAccepted", Palette.six)
        case .declined: ("inviteDeclined", Palette.wicket)
        }
        Text(key)
            .font(AppFont.body(11.5, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct DeclineReason: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening").font(.system(size: 11)).foregroundStyle(Palette.ink3)
            Text(verbatim: reason)
                .font(AppFont.body(13.5))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.sunk))
    }
}

/// "5 min. ago" from an ISO date string.
struct InviteTime: View {
    let date: String
    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: (ISODate.parse(date) ?? .now).formatted(.relative(presentation: .named).locale(locale)))
            .font(AppFont.body(12))
            .foregroundStyle(Palette.ink3)
    }
}

/// Declining asks for an optional reason, which the team owner sees.
struct DeclineInviteSheet: View {
    let invite: TeamMember
    let onDecline: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(title: "declineInviteTitle")
            Text("declineInviteBody \(invite.teamName)").font(AppFont.body(14)).foregroundStyle(Palette.ink2)
            TextField("declineReasonHint", text: $reason, axis: .vertical)
                .lineLimit(3...5)
                .fieldStyle()
                .onChange(of: reason) { _, v in if v.count > 200 { reason = String(v.prefix(200)) } }
            HStack(spacing: 10) {
                Button("cancel") { dismiss() }.secondaryButton()
                Button("decline") {
                    onDecline(reason)
                    dismiss()
                }
                .primaryButton(tint: Palette.wicket)
            }
        }
        .padding(24)
        .presentationDetents([.height(360)])
        .presentationCornerRadius(22)
    }
}

#if DEBUG
@MainActor private func previewModel(received: [TeamMember]? = TeamMember.receivedSamples,
                          sent: [TeamMember]? = TeamMember.sentSamples) -> InvitesModel {
    let m = InvitesModel(env: .preview())
    m.received = received
    m.sent = sent
    return m
}

#Preview("Invites") {
    NavigationStack {
        InvitesContent(model: previewModel())
            .screenBackground()
            .brandTitle("invitesTitle")
            .clearNavBar()
    }
    .previewEnvironment()
}

#Preview("Invites empty") {
    NavigationStack {
        InvitesContent(model: previewModel(received: [], sent: []))
            .screenBackground()
            .brandTitle("invitesTitle")
            .clearNavBar()
    }
    .previewEnvironment()
}

#Preview("Invites screen") {
    NavigationStack { InvitesView() }.previewEnvironment()
}

#Preview("Invite card") {
    InviteCard(invite: TeamMember.receivedSamples[0], onAccept: {}, onDecline: {})
        .padding()
        .screenBackground()
}

#Preview("Invite rows") {
    VStack(spacing: 10) {
        InviteRow(invite: TeamMember.receivedSamples[1], sent: false)
        InviteRow(invite: TeamMember.sentSamples[0], sent: true)
        InviteRow(invite: TeamMember.sentSamples[2], sent: true, onInviteAgain: {})
    }
    .padding()
    .screenBackground()
}

#Preview("Invite status tags") {
    HStack {
        InviteStatusTag(status: .pending)
        InviteStatusTag(status: .accepted)
        InviteStatusTag(status: .declined)
    }
    .padding()
}

#Preview("Decline reason") {
    DeclineReason(reason: "Playing for my office team this season.").padding()
}

#Preview("Invite time") {
    InviteTime(date: TeamMember.receivedSamples[0].invitedAt).padding()
}

#Preview("Decline sheet") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DeclineInviteSheet(invite: TeamMember.receivedSamples[0]) { _ in }
    }
}
#endif
