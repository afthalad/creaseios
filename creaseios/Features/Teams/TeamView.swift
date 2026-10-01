import SwiftUI
import PhotosUI
import CreaseEngine

@MainActor @Observable
final class TeamModel {
    var team: Team?
    var members: [TeamMember] = []
    var notFound = false
    var results: [PlayerProfile] = []
    var uploadingLogo = false
    var query = "" { didSet { scheduleSearch() } }
    private var searchTask: Task<Void, Never>?

    let teamID: String
    let env: AppEnvironment

    init(teamID: String, env: AppEnvironment) {
        self.teamID = teamID
        self.env = env
    }

    var accepted: [TeamMember] { members.filter { !$0.isPending } }
    func status(of playerID: String) -> MemberStatus? { members.first { $0.playerId == playerID }?.status }

    func watch() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await t in self.env.teams.watchTeam(self.teamID) {
                        await MainActor.run {
                            self.team = t
                            self.notFound = t == nil
                        }
                    }
                } catch {
                    await MainActor.run { self.notFound = true }
                }
            }
            group.addTask {
                do {
                    for try await m in self.env.teams.watchMembers(team: self.teamID) {
                        await MainActor.run { self.members = m }
                    }
                } catch {}
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? await env.players.search(query)) ?? []
        }
    }

    func invite(_ p: PlayerProfile) async {
        guard let team else { return }
        let m = TeamMember(teamId: team.id, teamName: team.name, ownerId: team.ownerId, ownerName: team.ownerName,
                           playerId: p.uid, playerName: p.name, playerGender: p.gender, playerPhotoUrl: p.photoUrl,
                           teamLogoUrl: team.logoUrl, status: .pending, invitedAt: ISODate.string(.now))
        do {
            try env.teams.invite(m)
            await env.functions.notify("team_invite", ["teamId": team.id, "playerId": p.uid])
        } catch {}
    }

    func remove(_ m: TeamMember) async { try? await env.teams.remove(m) }

    func setLogo(_ image: UIImage) async {
        guard let data = image.jpegForUpload(maxSide: 512, quality: 0.85) else { return }
        uploadingLogo = true
        defer { uploadingLogo = false }
        if let url = try? await env.functions.uploadPhoto(data, teamID: teamID) {
            try? await env.teams.setLogo(teamID, url: url)
        }
    }
}

struct TeamView: View {
    let teamID: String
    @Environment(AppEnvironment.self) private var env
    @State private var model: TeamModel?

    var body: some View {
        Group {
            if let model { TeamContent(model: model) } else { SkeletonList(count: 3) }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .brandNavBar()
        .task {
            let m = model ?? TeamModel(teamID: teamID, env: env)
            model = m
            await m.watch()
        }
    }
}

private struct TeamContent: View {
    @Bindable var model: TeamModel
    @Environment(SessionStore.self) private var session
    @State private var logoItem: PhotosPickerItem?
    @State private var searching = false

    private var isOwner: Bool { model.team?.ownerId == session.uid }

    var body: some View {
        Group {
            if model.notFound {
                MessageView(text: "errorNotFound", systemImage: "questionmark.circle")
            } else if let team = model.team {
                ScrollView {
                    VStack(spacing: 10) {
                        header(team)
                        ForEach(model.members) { memberRow($0, team: team) }
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isOwner {
                        Button { searching = true } label: {
                            Label("addPlayers", systemImage: "person.badge.plus")
                                .font(AppFont.body(15, .bold))
                                .foregroundStyle(Palette.onAccent)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .controlSize(.large)
                        .padding(20)
                    }
                }
            } else {
                SkeletonList(count: 3)
            }
        }
        .navigationTitle(Text(verbatim: model.team?.name ?? ""))
        .sheet(isPresented: $searching) { PlayerSearchSheet(model: model) }
        .onChange(of: logoItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await model.setLogo(img)
                }
            }
        }
    }

    private func header(_ team: Team) -> some View {
        VStack(spacing: 10) {
            ZStack {
                TeamBadge(shortName: team.shortName, color: Palette.brand2, logoURL: team.logoUrl, size: 72, circular: true)
                if model.uploadingLogo { ProgressView().tint(.white) }
            }
            .overlay(alignment: .bottomTrailing) {
                if isOwner {
                    PhotosPicker(selection: $logoItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.onAccent)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Palette.accent))
                    }
                }
            }
            Text(verbatim: team.name).font(AppFont.heading(22, .bold)).foregroundStyle(Palette.ink)
            Text("playersCount \(model.accepted.count)").font(AppFont.body(13)).foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func memberRow(_ m: TeamMember, team: Team) -> some View {
        HStack(spacing: 12) {
            PlayerPhoto(photoURL: m.playerPhotoUrl, gender: m.playerGender, size: 44)
            Text(verbatim: m.playerName).font(AppFont.body(15, .medium)).foregroundStyle(Palette.ink)
            Spacer()
            if m.playerId == team.ownerId {
                Text("teamOwner").font(AppFont.body(13, .medium)).foregroundStyle(Palette.ink3)
            } else {
                if m.isPending { Text("memberPending").font(AppFont.body(13, .semibold)).foregroundStyle(Palette.extra) }
                if isOwner {
                    Button { Task { await model.remove(m) } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.ink3)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Palette.sunk))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("removeMember"))
                }
            }
        }
        .card(padding: 12)
    }
}

private struct PlayerSearchSheet: View {
    @Bindable var model: TeamModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.query.trimmed.isEmpty && model.results.isEmpty {
                    Text("searchNoResults").foregroundStyle(Palette.ink3)
                }
                ForEach(model.results) { p in
                    HStack(spacing: 12) {
                        PlayerPhoto(photoURL: p.photoUrl, gender: p.gender, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: p.name).font(AppFont.body(15, .semibold)).foregroundStyle(Palette.ink)
                            Text(verbatim: p.summary(locale)).font(AppFont.body(12)).foregroundStyle(Palette.ink3)
                        }
                        Spacer()
                        switch model.status(of: p.uid) {
                        case .accepted: Text("inTeam").font(AppFont.body(13, .medium)).foregroundStyle(Palette.ink3)
                        case .pending: Text("invited").font(AppFont.body(13, .semibold)).foregroundStyle(Palette.extra)
                        case nil:
                            Button("invite") { Task { await model.invite(p) } }
                                .font(AppFont.body(13, .bold))
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.btn)
                        }
                    }
                }
            }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("searchPlayers"))
            .navigationTitle("addPlayers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ok") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
