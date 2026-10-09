import SwiftUI
import PhotosUI

@MainActor @Observable
final class TeamsModel {
    var memberships: [TeamMember]?
    var invites: [TeamMember] { memberships?.filter(\.isPending) ?? [] }
    var teams: [TeamMember] { memberships?.filter(\.isAccepted) ?? [] }
    let env: AppEnvironment

    init(env: AppEnvironment) { self.env = env }

    func watch(uid: String) async {
        do { for try await m in env.teams.watchMemberships(player: uid) { memberships = m } } catch { memberships = [] }
    }

    /// Returns the new team ID, or nil on failure.
    func createTeam(name: String, logo: UIImage?, owner: UserProfile, player: PlayerProfile?) async -> String? {
        let id = UUID().uuidString.lowercased()
        let now = ISODate.string(.now)
        var logoURL: String?
        if let data = logo?.jpegForUpload(maxSide: 512, quality: 0.85) {
            do { logoURL = try await env.photos.upload(data, teamID: id) } catch { return nil }
        }
        let trimmed = name.trimmed
        let team = Team(id: id, name: trimmed, shortName: shortName(trimmed), ownerId: owner.uid,
                        ownerName: owner.name, createdAt: now, logoUrl: logoURL, searchTokens: searchTokens(trimmed))
        let me = TeamMember(teamId: id, teamName: trimmed, ownerId: owner.uid, ownerName: owner.name,
                            playerId: owner.uid, playerName: player?.name ?? owner.name, playerGender: player?.gender,
                            playerPhotoUrl: player?.photoUrl, teamLogoUrl: logoURL, status: .accepted, invitedAt: now)
        do {
            try await env.teams.create(team, owner: me)
            return id
        } catch {
            return nil
        }
    }
}

struct TeamsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var model: TeamsModel?

    var body: some View {
        Group {
            if let model { TeamsContent(model: model) } else { SkeletonList(count: 3) }
        }
        .smoothChange(model == nil)
        .screenBackground()
        .brandTitle("teams")
        .clearNavBar()
        .task(id: session.uid) {
            guard let uid = session.uid else { return }
            let m = model ?? TeamsModel(env: env)
            model = m
            await m.watch(uid: uid)
        }
    }
}

private struct TeamsContent: View {
    let model: TeamsModel
    @Environment(Router.self) private var router
    @State private var declining: TeamMember?
    @State private var failed = false

    var body: some View {
        @Bindable var router = router
        ScrollView {
            content
                .padding(16)
                .smoothChange(model.memberships)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { router.push(.invites) } label: {
                    IconBadge(systemName: "envelope", count: model.invites.count)
                }
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(Text("invitesTitle"))
                Button { router.creatingTeam = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(Text("newTeam"))
            }
            .withoutGlass()
        }
        .sheet(isPresented: $router.creatingTeam) {
            NewTeamSheet(model: model) { id in router.push(.team(id: id)) }
        }
        .sheet(item: $declining) { invite in
            DeclineInviteSheet(invite: invite) { reason in
                run { await model.env.decline(invite, reason: reason) }
            }
        }
        .alert("inviteActionFailed", isPresented: $failed) { Button("ok") {} }
    }

    private func run(_ action: @escaping () async -> Bool) {
        Task { if await !action() { failed = true } }
    }

    @ViewBuilder
    private var content: some View {
        if model.memberships == nil {
            SkeletonList(count: 3)
        } else {
            VStack(spacing: 10) {
                if !model.invites.isEmpty {
                    SectionHeader(title: "teamInvites", count: model.invites.count)
                    ForEach(model.invites) { invite in
                        InviteCard(invite: invite) {
                            if await !model.env.accept(invite) { failed = true }
                        } onDecline: {
                            declining = invite
                        }
                    }
                }
                if model.teams.isEmpty {
                    if model.invites.isEmpty {
                        MessageView(text: "teamsEmpty", systemImage: "person.3")
                        Button("createTeam") { router.creatingTeam = true }
                            .font(AppFont.body(15, .semibold))
                            .foregroundStyle(Palette.six)
                            .padding(.top, 4)
                    }
                } else {
                    SectionHeader(title: "myTeams", count: model.teams.count)
                    ForEach(model.teams) { m in
                        Button { router.push(.team(id: m.teamId)) } label: { TeamRow(member: m) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct TeamRow: View {
    let member: TeamMember

    var body: some View {
        HStack(spacing: 12) {
            TeamBadge(shortName: shortName(member.teamName), color: Palette.brand2, logoURL: member.teamLogoUrl, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: member.teamName).font(AppFont.body(16, .semibold)).foregroundStyle(Palette.ink)
                Group {
                    if member.isOwner { Text("teamOwner") } else { Text(verbatim: member.ownerName) }
                }
                .font(AppFont.body(13))
                .foregroundStyle(Palette.ink3)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink3)
        }
        .card()
    }
}

private struct NewTeamSheet: View {
    let model: TeamsModel
    let onCreated: (String) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var logo: UIImage?
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            SheetTitle(title: "newTeam")
            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 8) {
                    TeamBadge(shortName: shortName(name), color: Palette.brand2, image: logo, size: 72, circular: true)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.onHighlight)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Palette.highlight))
                        }
                    Text("photoChoose").font(AppFont.body(13, .semibold)).foregroundStyle(Palette.six)
                }
            }
            TextField("teamName", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .fieldStyle()
            if failed { Text("teamCreateError").font(AppFont.body(13)).foregroundStyle(Palette.wicket) }
            HStack(spacing: 10) {
                Button("cancel") { dismiss() }.secondaryButton()
                Button { Task { await create() } } label: {
                    if saving { ProgressView().tint(Palette.onBrand) } else { Text("createTeam") }
                }
                .primaryButton()
                .disabled(name.trimmed.isEmpty || saving)
            }
        }
        .padding(24)
        .presentationDetents([.height(400)])
        .presentationCornerRadius(22)
        .onChange(of: pickerItem) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self) { logo = UIImage(data: d) } }
        }
    }

    private func create() async {
        guard let owner = session.profile else { return }
        saving = true
        failed = false
        let id = await model.createTeam(name: name, logo: logo, owner: owner, player: session.player)
        saving = false
        if let id {
            dismiss()
            onCreated(id)
        } else {
            failed = true
        }
    }
}

#if DEBUG
@MainActor private func previewModel(_ memberships: [TeamMember]?) -> TeamsModel {
    let m = TeamsModel(env: .preview())
    m.memberships = memberships
    return m
}

@MainActor private func previewScreen(_ memberships: [TeamMember]?) -> some View {
    NavigationStack {
        TeamsContent(model: previewModel(memberships))
            .screenBackground()
            .brandTitle("teams")
            .clearNavBar()
    }
    .previewEnvironment()
}

#Preview("Teams") {
    previewScreen([TeamMember.receivedSamples[0], .sample("Kasun Perera"), TeamMember.receivedSamples[1]])
}

#Preview("Teams empty") { previewScreen([]) }

#Preview("Teams loading") { previewScreen(nil) }

#Preview("Team row") {
    TeamRow(member: .sample("Kasun Perera")).padding().screenBackground()
}

#Preview("New team sheet") {
    Color.clear.sheet(isPresented: .constant(true)) { NewTeamSheet(model: previewModel([])) { _ in } }
        .previewEnvironment()
}
#endif
