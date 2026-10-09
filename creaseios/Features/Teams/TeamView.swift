import SwiftUI
import PhotosUI

struct PlayerStats: Hashable {
    var runs = 0, balls = 0, wickets = 0
    var strikeRate: String { balls == 0 ? "–" : String(format: "%.0f", Double(runs) * 100 / Double(balls)) }
}

@MainActor @Observable
final class TeamModel {
    var team: Team?
    var members: [TeamMember] = []
    var notFound = false
    var results: [PlayerProfile] = []
    var uploadingLogo = false
    var searching = false
    var profiles: [String: PlayerProfile] = [:]
    var stats: [String: PlayerStats] = [:]
    var query = "" { didSet { scheduleSearch() } }
    private var searchTask: Task<Void, Never>?

    let teamID: String
    let env: AppEnvironment

    init(teamID: String, env: AppEnvironment) {
        self.teamID = teamID
        self.env = env
    }

    /// Invites still waiting or turned down, newest first.
    var invites: [TeamMember] { members.filter { !$0.isAccepted }.sorted { $0.invitedAt > $1.invitedAt } }
    func member(_ playerID: String) -> TeamMember? { members.first { $0.playerId == playerID } }

    /// Captain first, then vice captain, then everyone else in the order they joined.
    var accepted: [TeamMember] {
        let rank: (TeamMember) -> Int = { [team] m in
            m.playerId == team?.captainId ? 0 : m.playerId == team?.viceCaptainId ? 1 : 2
        }
        return members.filter(\.isAccepted).sorted { (rank($0), $0.invitedAt) < (rank($1), $1.invitedAt) }
    }

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
                        await self.loadProfiles(for: m.map(\.playerId))
                    }
                } catch {}
            }
            group.addTask { await self.loadStats() }
        }
    }

    private func loadProfiles(for ids: [String]) async {
        let players = env.players
        let missing = ids.filter { profiles[$0] == nil }
        let found = await withTaskGroup(of: PlayerProfile?.self) { group in
            for id in missing { group.addTask { try? await players.get(id) } }
            var list: [PlayerProfile] = []
            for await p in group { if let p { list.append(p) } }
            return list
        }
        for p in found { profiles[p.uid] = p }
    }

    /// Career figures for this team's players, replayed from every match the viewer can read.
    func loadStats() async {
        let repo = env.matches
        guard let matches = try? await repo.teamMatches(teamID, uid: env.session.uid) else { return }
        let played = matches.filter { [.live, .completed, .abandoned].contains($0.status) }
        let logs = await withTaskGroup(of: (Match, [MatchEvent])?.self) { group in
            for match in played {
                group.addTask { (try? await repo.loadEvents(match.id)).map { (match, $0) } }
            }
            var list: [(Match, [MatchEvent])] = []
            for await log in group { if let log { list.append(log) } }
            return list
        }
        var totals: [String: PlayerStats] = [:]
        for (match, events) in logs {
            let state = env.engine.replay(events: events, config: match.config, inningsBattingTeam: match.inningsBattingOrder)
            for inn in state.innings {
                for (id, b) in inn.batters { totals[id, default: .init()].runs += b.runs; totals[id, default: .init()].balls += b.balls }
                for (id, s) in inn.bowlers { totals[id, default: .init()].wickets += s.wickets }
            }
        }
        stats = totals
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            let found = (try? await env.players.search(query)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    func invite(_ p: PlayerProfile) async -> Bool {
        guard let team else { return false }
        let m = TeamMember(teamId: team.id, teamName: team.name, ownerId: team.ownerId, ownerName: team.ownerName,
                           playerId: p.uid, playerName: p.name, playerGender: p.gender, playerPhotoUrl: p.photoUrl,
                           teamLogoUrl: team.logoUrl, status: .pending, invitedAt: ISODate.string(.now))
        return await env.sendInvite(m)
    }

    func remove(_ m: TeamMember) async {
        if m.playerId == team?.captainId || m.playerId == team?.viceCaptainId {
            await setCaptains(captain: team?.captainId == m.playerId ? nil : team?.captainId,
                              vice: team?.viceCaptainId == m.playerId ? nil : team?.viceCaptainId)
        }
        try? await env.teams.remove(m)
    }

    func setCaptains(captain: String?, vice: String?) async {
        try? await env.teams.setCaptains(teamID, captain: captain, vice: vice == captain ? nil : vice)
    }

    func setLogo(_ image: UIImage) async {
        guard let data = image.jpegForUpload(maxSide: 512, quality: 0.85) else { return }
        uploadingLogo = true
        defer { uploadingLogo = false }
        if let url = try? await env.photos.upload(data, teamID: teamID) {
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
        .smoothChange(model == nil)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            let m = model ?? TeamModel(teamID: teamID, env: env)
            model = m
            await m.watch()
        }
    }
}

private enum TeamTab: Hashable { case players, info }

private struct TeamContent: View {
    @Bindable var model: TeamModel
    @Environment(SessionStore.self) private var session
    @State private var tab = TeamTab.players
    @State private var searching = false
    @State private var editing = false
    @State private var failed = false

    private var isOwner: Bool { model.team?.ownerId == session.uid }

    var body: some View {
        Group {
            if model.notFound {
                MessageView(text: "errorNotFound", systemImage: "questionmark.circle")
            } else if let team = model.team {
                ScrollView {
                    VStack(spacing: 0) {
                        header(team)
                        UnderlineTabs(tabs: [(.players, "teamTabPlayers"), (.info, "teamTabInfo")], selection: $tab)
                            .background(Palette.surface)
                        Group {
                            switch tab {
                            case .players: playersTab(team)
                            case .info: infoTab(team)
                            }
                        }
                        .padding(16)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else {
                SkeletonList(count: 3)
            }
        }
        .smoothChange(model.team == nil)
        .smoothChange(model.notFound)
        .smoothChange(model.members)
        .smoothChange(model.stats)
        .smoothChange(tab)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { searching = true } label: { Image(systemName: "plus") }
                        .tint(.white)
                        .accessibilityLabel(Text("addPlayers"))
                }
            }
        }
        .sheet(isPresented: $searching) { PlayerSearchSheet(model: model) }
        .sheet(isPresented: $editing) { EditTeamSheet(model: model) }
        .alert("inviteActionFailed", isPresented: $failed) { Button("ok") {} }
    }

    private func header(_ team: Team) -> some View {
        Image("welcome_hero")
            .resizable()
            .scaledToFill()
            .frame(height: 290)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.1), .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 16) {
                    ZStack {
                        TeamBadge(shortName: team.shortName, color: Palette.brand2, logoURL: team.logoUrl, size: 92, circular: true)
                        if model.uploadingLogo { ProgressView().tint(.white) }
                    }
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text(verbatim: team.name).font(AppFont.heading(28, .bold)).foregroundStyle(.white).lineLimit(1)
                            if isOwner {
                                Button { editing = true } label: { Image(systemName: "pencil").font(.system(size: 18, weight: .semibold)) }
                                    .foregroundStyle(.white)
                                    .accessibilityLabel(Text("editTeam"))
                            }
                        }
                        Text("playersCount \(model.accepted.count)").font(AppFont.body(15)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
    }

    @ViewBuilder
    private func playersTab(_ team: Team) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: "#").frame(width: 22, alignment: .leading)
                Text("teamColPlayer").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 48)
                Text("teamColRuns").frame(width: 38, alignment: .trailing)
                Text("teamColWickets").frame(width: 34, alignment: .trailing)
                Text("teamColSR").frame(width: 34, alignment: .trailing)
            }
            .font(AppFont.body(11.5, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            ForEach(Array(model.accepted.enumerated()), id: \.element.id) { i, m in
                Divider().overlay(Palette.line)
                playerRow(i + 1, m, team: team)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.surface))

        if isOwner && !model.invites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "invited", count: model.invites.count)
                ForEach(model.invites) { m in
                    InviteRow(invite: m, sent: true) {
                        if await !model.env.inviteAgain(m) { failed = true }
                    }
                        .contextMenu { removeButton(m) }
                }
            }
            .padding(.top, 20)
        }
    }

    private func playerRow(_ n: Int, _ m: TeamMember, team: Team) -> some View {
        let s = model.stats[m.playerId]
        return HStack(spacing: 8) {
            Text(verbatim: String(format: "%02d", n))
                .font(AppFont.mono(13, .medium))
                .foregroundStyle(Palette.ink3)
                .frame(width: 22, alignment: .leading)
            PlayerPhoto(photoURL: m.playerPhotoUrl, gender: m.playerGender, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: m.playerName)
                    .font(AppFont.body(15, .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                tag(for: m, team: team)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text(verbatim: s.map { "\($0.runs)" } ?? "–").frame(width: 38, alignment: .trailing)
                Text(verbatim: s.map { "\($0.wickets)" } ?? "–").frame(width: 34, alignment: .trailing)
                Text(verbatim: s?.strikeRate ?? "–").frame(width: 34, alignment: .trailing)
            }
            .font(AppFont.mono(13, .medium))
            .foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            if isOwner {
                Button { Task { await model.setCaptains(captain: m.playerId, vice: team.viceCaptainId) } } label: {
                    Label("makeCaptain", systemImage: "c.circle")
                }
                Button { Task { await model.setCaptains(captain: team.captainId == m.playerId ? nil : team.captainId, vice: m.playerId) } } label: {
                    Label("makeViceCaptain", systemImage: "v.circle")
                }
                if m.playerId != team.ownerId { removeButton(m) }
            }
        }
    }

    private func removeButton(_ m: TeamMember) -> some View {
        Button(role: .destructive) { Task { await model.remove(m) } } label: {
            Label("removeMember", systemImage: "person.badge.minus")
        }
    }

    private func tag(for m: TeamMember, team: Team) -> some View {
        let (key, color): (LocalizedStringKey, Color) = {
            if m.playerId == team.captainId { return ("captain", Palette.six) }
            if m.playerId == team.viceCaptainId { return ("viceCaptain", Palette.four) }
            switch model.profiles[m.playerId]?.role ?? .batter {
            case .batter: return ("roleBatter", Palette.six)
            case .bowler: return ("roleBowler", Palette.wicket)
            case .allRounder: return ("roleAllRounder", Palette.allRounder)
            case .wicketKeeper: return ("roleWicketKeeper", Palette.extra)
            }
        }()
        return Text(key)
            .font(AppFont.body(11.5, .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func infoTab(_ team: Team) -> some View {
        let name: (String?) -> String = { id in model.members.first { $0.playerId == id }?.playerName ?? "–" }
        let created = ISODate.parse(team.createdAt).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "–"
        let rows: [(LocalizedStringKey, String)] = [
            ("teamInfoShortName", team.shortName),
            ("teamOwner", team.ownerName.isEmpty ? name(team.ownerId) : team.ownerName),
            ("captain", name(team.captainId)),
            ("viceCaptain", name(team.viceCaptainId)),
            ("teamTabPlayers", "\(model.accepted.count)"),
            ("teamInfoCreated", created),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Divider().overlay(Palette.line) }
                HStack {
                    Text(row.0).font(AppFont.body(15)).foregroundStyle(Palette.ink3)
                    Spacer()
                    Text(verbatim: row.1).font(AppFont.body(15, .semibold)).foregroundStyle(Palette.ink)
                }
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.surface))
    }
}

private struct EditTeamSheet: View {
    let model: TeamModel
    @Environment(\.dismiss) private var dismiss
    @State private var logoItem: PhotosPickerItem?
    @State private var captain: String?
    @State private var vice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $logoItem, matching: .images) {
                        HStack(spacing: 14) {
                            TeamBadge(shortName: model.team?.shortName ?? "", color: Palette.brand2,
                                      logoURL: model.team?.logoUrl, size: 52, circular: true)
                            Text("teamChangeLogo")
                            if model.uploadingLogo { Spacer(); ProgressView() }
                        }
                    }
                }
                Section {
                    Picker("captain", selection: $captain) { options }
                    Picker("viceCaptain", selection: $vice) { options }
                }
            }
            .navigationTitle("editTeam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        Task { await model.setCaptains(captain: captain, vice: vice) }
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            captain = model.team?.captainId
            vice = model.team?.viceCaptainId
        }
        .onChange(of: logoItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await model.setLogo(img)
                }
            }
        }
    }

    @ViewBuilder private var options: some View {
        Text("teamNone").tag(String?.none)
        ForEach(model.accepted) { m in Text(verbatim: m.playerName).tag(Optional(m.playerId)) }
    }
}

private struct PlayerSearchSheet: View {
    @Bindable var model: TeamModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    @State private var inviting: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if model.searching && model.results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if !model.query.trimmed.isEmpty && model.results.isEmpty {
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
                        let member = model.member(p.uid)
                        switch member?.status {
                        case .accepted: Text("inTeam").font(AppFont.body(13, .medium)).foregroundStyle(Palette.ink3)
                        case .pending: Text("invited").font(AppFont.body(13, .semibold)).foregroundStyle(Palette.extra)
                        case .declined, nil:
                            if inviting.contains(p.uid) {
                                ProgressView()
                            } else {
                                Button(member == nil ? "invite" : "inviteAgain") { invite(p) }
                                    .font(AppFont.body(13, .bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(Palette.btn)
                            }
                        }
                    }
                }
            }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("searchPlayers"))
            .navigationTitle("addPlayers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("ok") { dismiss() } } }
            .alert("inviteActionFailed", isPresented: $failed) { Button("ok") {} }
            .smoothChange(model.results)
            .smoothChange(model.members)
        }
        .presentationDetents([.large])
    }

    private func invite(_ p: PlayerProfile) {
        inviting.insert(p.uid)
        Task {
            if await !model.invite(p) { failed = true }
            inviting.remove(p.uid)
        }
    }
}

#if DEBUG
@MainActor private func previewModel() -> TeamModel {
    let m = TeamModel(teamID: Team.sample.id, env: .preview())
    m.team = .sample
    m.members = TeamMember.teamSamples
    m.stats = ["kasun": PlayerStats(runs: 214, balls: 160, wickets: 6), "dilan": PlayerStats(runs: 98, balls: 91)]
    m.results = PlayerProfile.samples
    return m
}

#Preview("Team") {
    NavigationStack {
        TeamContent(model: previewModel())
            .screenBackground()
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .previewEnvironment()
}

#Preview("Team as visitor") {
    NavigationStack { TeamContent(model: previewModel()).screenBackground() }
        .previewEnvironment(signedIn: false)
}

#Preview("Team loading") {
    NavigationStack { TeamView(teamID: Team.sample.id) }.previewEnvironment()
}

#Preview("Edit team sheet") {
    Color.clear.sheet(isPresented: .constant(true)) { EditTeamSheet(model: previewModel()) }
}

#Preview("Player search sheet") {
    Color.clear.sheet(isPresented: .constant(true)) { PlayerSearchSheet(model: previewModel()) }
}
#endif
