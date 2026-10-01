import SwiftUI
import CreaseEngine

@MainActor @Observable
final class CreateMatchModel {
    struct Side {
        var team: Team?
        var chosen = false
        var name: String
        var short: String
        var color: Int
        var squad: [Player] = []

        static let defaultA = Side(name: "Team A", short: "TMA", color: 0xFF0F3B29)
        static let defaultB = Side(name: "Team B", short: "TMB", color: 0xFF2E7DD1)
    }

    var step = 0
    var format: MatchFormat = .t20 {
        didSet {
            overs = format.defaultOvers
            players = format.defaultPlayersPerSide
        }
    }
    var overs = 20
    var players = 11
    var venue = ""
    var isPublic = true
    var a = Side.defaultA
    var b = Side.defaultB
    var tossWinner: String?
    var tossDecision: TossDecision?
    var submitting = false
    var failed = false

    let env: AppEnvironment
    let creatorID: String?

    init(env: AppEnvironment, creatorID: String?) {
        self.env = env
        self.creatorID = creatorID
    }

    var sameTeam: Bool { a.team != nil && a.team?.id == b.team?.id }
    var canProceedFromTeams: Bool { a.chosen && b.chosen && !sameTeam }
    var canSubmit: Bool { tossWinner != nil && tossDecision != nil && !submitting }
    var canProceed: Bool {
        switch step {
        case 1: canProceedFromTeams
        case 3: canSubmit
        default: true
        }
    }

    /// Owners of picked teams other than me must confirm before play.
    var pendingOwnerIDs: [String] {
        Array(Set([a.team, b.team].compactMap { $0?.ownerId }.filter { $0 != creatorID })).sorted()
    }

    func side(_ s: String) -> Side { s == "A" ? a : b }

    func update(_ s: String, _ change: (inout Side) -> Void) {
        if s == "A" { change(&a) } else { change(&b) }
    }

    func select(_ team: Team, side: String) async {
        let members = (try? await env.teams.acceptedMembers(team.id)) ?? []
        let squad = members.map { Player(id: $0.playerId, name: $0.playerName, photoUrl: $0.playerPhotoUrl) }
        let color = side == "A" ? Side.defaultA.color : Side.defaultB.color
        update(side) { $0 = Side(team: team, chosen: true, name: team.name, short: team.shortName, color: color, squad: squad) }
    }

    func chooseCustom(side: String) {
        update(side) { $0 = side == "A" ? Side.defaultA : Side.defaultB; $0.chosen = true }
    }

    func addPlayer(_ name: String, side: String) {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return }
        update(side) { $0.squad.append(Player(id: UUID().uuidString.lowercased(), name: trimmed)) }
    }

    func submit() async -> (id: String, pending: Bool)? {
        guard let tossWinner, let tossDecision else { return nil }
        submitting = true
        defer { submitting = false }

        func team(_ s: Side, _ side: String) -> MatchTeam {
            MatchTeam(side: side, name: s.name.trimmed, shortName: s.short.trimmed.uppercased(), color: s.color,
                      squad: s.squad, teamId: s.team?.id, ownerId: s.team?.ownerId, logoUrl: s.team?.logoUrl)
        }

        let pending = pendingOwnerIDs
        var m = Match(format: format, config: MatchConfig(oversPerInnings: overs, playersPerSide: players),
                      teamA: team(a, "A"), teamB: team(b, "B"), createdAt: ISODate.string(.now))
        m.id = UUID().uuidString.lowercased()
        m.venueName = venue.trimmed.isEmpty ? nil : venue.trimmed
        m.toss = Toss(winnerSide: tossWinner, decision: tossDecision)
        m.status = pending.isEmpty ? .live : .pending
        m.createdBy = creatorID
        m.isPublic = isPublic
        m.pendingOwnerIds = pending
        do {
            try env.matches.create(m)
            if !pending.isEmpty { await env.functions.notify("match_request", ["matchId": m.id]) }
            return (m.id, !pending.isEmpty)
        } catch {
            failed = true
            return nil
        }
    }
}

struct CreateMatchWizard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var model: CreateMatchModel?

    var body: some View {
        Group {
            if let model { CreateMatchContent(model: model) } else { Color.clear }
        }
        .onAppear { if model == nil { model = CreateMatchModel(env: env, creatorID: session.uid) } }
    }
}

private struct CreateMatchContent: View {
    @Bindable var model: CreateMatchModel
    @Environment(Router.self) private var router
    @State private var pickingSide: PickingSide?

    private let titles: [LocalizedStringKey] = ["createDetails", "createTeams", "tabSquads", "createToss"]

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.step {
                    case 0: DetailsStep(model: model)
                    case 1: TeamsStep(model: model) { pickingSide = PickingSide(side: $0) }
                    case 2: SquadsStep(model: model)
                    default: TossStep(model: model)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .screenBackground()
        .navigationTitle(titles[model.step])
        .navigationBarTitleDisplayMode(.inline)
        .brandNavBar()
        .sheet(item: $pickingSide) { picking in
            let side = picking.side
            TeamPickerSheet(side: side) { team in
                if let team { Task { await model.select(team, side: side) } } else { model.chooseCustom(side: side) }
            }
        }
        .alert("errorGeneric", isPresented: $model.failed) { Button("ok") {} }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule().fill(i <= model.step ? Palette.accent : .white.opacity(0.15)).frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.brand)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.step > 0 {
                Button("back") { withAnimation { model.step -= 1 } }.secondaryButton()
            }
            Button {
                if model.step < 3 { withAnimation { model.step += 1 } } else { Task { await submit() } }
            } label: {
                if model.submitting { ProgressView().tint(Palette.onBrand) }
                else if model.step < 3 { Text("next") }
                else { Text(model.pendingOwnerIDs.isEmpty ? "startScoring" : "sendForConfirmation") }
            }
            .primaryButton()
            .disabled(!model.canProceed)
        }
        .padding(16)
        .background(Palette.surface.ignoresSafeArea())
    }

    private func submit() async {
        guard let result = await model.submit() else { return }
        router.replace(with: result.pending ? .matchCenter(matchID: result.id) : .scoring(matchID: result.id))
    }
}

private struct PickingSide: Identifiable {
    let side: String
    var id: String { side }
}

private struct FieldLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title).font(AppFont.body(13, .semibold)).foregroundStyle(Palette.ink3)
    }
}

private struct DetailsStep: View {
    @Bindable var model: CreateMatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: "format")
            FlowLayout {
                ForEach(MatchFormat.allCases, id: \.self) { f in
                    ChoiceChip(title: f.label, selected: model.format == f) { model.format = f }
                }
            }
        }
        .card()

        VStack(spacing: 4) {
            Stepper(value: $model.overs, in: 1...50) { stepperLabel("oversPerInnings", model.overs) }
            Divider()
            Stepper(value: $model.players, in: 2...11) { stepperLabel("playersPerSide", model.players) }
        }
        .card()

        VStack(alignment: .leading, spacing: 12) {
            TextField("venueOptional", text: $model.venue).fieldStyle()
            Toggle(isOn: $model.isPublic) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("publicMatch").font(AppFont.body(15, .semibold)).foregroundStyle(Palette.ink)
                    Text(model.isPublic ? "publicMatchOn" : "publicMatchOff").font(AppFont.body(13)).foregroundStyle(Palette.ink3)
                }
            }
            .tint(Palette.six)
        }
        .card()
    }

    private func stepperLabel(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack {
            Text(title).font(AppFont.body(15, .medium)).foregroundStyle(Palette.ink)
            Spacer()
            Text(verbatim: "\(value)").font(AppFont.mono(16, .semibold)).foregroundStyle(Palette.ink)
        }
    }
}

private struct TeamsStep: View {
    @Bindable var model: CreateMatchModel
    let pick: (String) -> Void
    private let swatches: [Int] = [0xFF0F3B29, 0xFF2E7DD1, 0xFFC9650F, 0xFFD0263A, 0xFF7B3FC4, 0xFF0F7A7A, 0xFF141813]

    var body: some View {
        ForEach(["A", "B"], id: \.self) { side in sideCard(side) }
        if model.sameTeam {
            Text("sameTeamError").font(AppFont.body(14)).foregroundStyle(Palette.wkt)
        }
    }

    private func sideCard(_ s: String) -> some View {
        let side = model.side(s)
        return VStack(alignment: .leading, spacing: 12) {
            Button { pick(s) } label: {
                HStack(spacing: 12) {
                    TeamBadge(shortName: side.short, color: Color(argb: side.color), logoURL: side.team?.logoUrl, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if side.chosen { Text(verbatim: side.name) } else { Text("chooseTeam") }
                        }
                        .font(AppFont.heading(17, .bold))
                        .foregroundStyle(Palette.ink)
                        Group {
                            if let team = side.team { Text(verbatim: team.ownerName) }
                            else if side.chosen { Text("customTeam") }
                            else { Text(verbatim: s == "A" ? "Team A" : "Team B") }
                        }
                        .font(AppFont.body(13))
                        .foregroundStyle(Palette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if side.chosen && side.team == nil {
                HStack(spacing: 10) {
                    TextField("teamName", text: binding(s, \.name)).autocorrectionDisabled().fieldStyle()
                    TextField("teamShort", text: binding(s, \.short))
                        .textInputAutocapitalization(.characters)
                        .fieldStyle()
                        .frame(width: 96)
                }
                HStack(spacing: 10) {
                    ForEach(swatches, id: \.self) { c in
                        Circle()
                            .fill(Color(argb: c))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Palette.accent, lineWidth: side.color == c ? 3 : 0))
                            .onTapGesture { model.update(s) { $0.color = c } }
                    }
                }
            }
        }
        .card()
    }

    private func binding(_ s: String, _ key: WritableKeyPath<CreateMatchModel.Side, String>) -> Binding<String> {
        Binding(get: { model.side(s)[keyPath: key] }, set: { v in model.update(s) { $0[keyPath: key] = v } })
    }
}

private struct SquadsStep: View {
    @Bindable var model: CreateMatchModel
    @State private var newNames = ["A": "", "B": ""]

    var body: some View {
        ForEach(["A", "B"], id: \.self) { s in
            let side = model.side(s)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TeamBadge(shortName: side.short, color: Color(argb: side.color), logoURL: side.team?.logoUrl, size: 30)
                    Text(verbatim: side.name).font(AppFont.heading(17, .bold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("squadCount \(side.squad.count)").font(AppFont.mono(13)).foregroundStyle(Palette.ink3)
                }
                ForEach(side.squad) { p in
                    HStack(spacing: 10) {
                        PlayerAvatar(name: p.name, photoURL: p.photoUrl, size: 32, teamColor: Color(argb: side.color))
                        Text(verbatim: p.name).font(AppFont.body(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        Button { model.update(s) { $0.squad.removeAll { $0.id == p.id } } } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField("playerName", text: Binding(get: { newNames[s] ?? "" }, set: { newNames[s] = $0 }))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { add(s) }
                        .fieldStyle()
                    Button { add(s) } label: {
                        Image(systemName: "plus").fontWeight(.bold).foregroundStyle(Palette.onAccent)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .controlSize(.large)
                }
                if side.squad.count < 2 {
                    Text("addTwoPlayers").font(AppFont.body(12.5)).foregroundStyle(Palette.ink3)
                }
            }
            .card()
        }
    }

    private func add(_ side: String) {
        model.addPlayer(newNames[side] ?? "", side: side)
        newNames[side] = ""
    }
}

private struct TossStep: View {
    @Bindable var model: CreateMatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tossWinner").font(AppFont.heading(17, .bold)).foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                ForEach(["A", "B"], id: \.self) { s in
                    let side = model.side(s)
                    option(selected: model.tossWinner == s) {
                        model.tossWinner = s
                    } label: {
                        VStack(spacing: 8) {
                            TeamBadge(shortName: side.short, color: Color(argb: side.color), logoURL: side.team?.logoUrl, size: 40)
                            Text(verbatim: side.name).font(AppFont.body(14, .semibold)).lineLimit(1)
                        }
                    }
                }
            }
        }
        .card()

        VStack(alignment: .leading, spacing: 12) {
            Text("electedTo").font(AppFont.heading(17, .bold)).foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                ForEach(TossDecision.allCases, id: \.self) { d in
                    option(selected: model.tossDecision == d) {
                        model.tossDecision = d
                    } label: {
                        Text(d.label).font(AppFont.body(15, .semibold))
                    }
                }
            }
        }
        .card()
    }

    private func option<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Palette.brand : Palette.sunk))
        }
        .buttonStyle(.plain)
    }
}

struct TeamPickerSheet: View {
    let side: String
    let onPick: (Team?) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var mine: [Team] = []
    @State private var query = ""
    @State private var results: [Team] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(nil)
                }
                if query.trimmed.isEmpty {
                    if !mine.isEmpty {
                        Section("myTeams") { ForEach(mine) { row($0) } }
                    }
                } else {
                    Section { ForEach(results) { row($0) } }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("searchTeams"))
            .navigationTitle("chooseTeam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("cancel") { dismiss() } } }
            .task {
                guard let uid = session.uid else { return }
                mine = (try? await env.teams.ownedBy(uid)) ?? []
            }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                results = (try? await env.teams.search(query)) ?? []
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(22)
    }

    private func row(_ team: Team?) -> some View {
        Button {
            onPick(team)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if let team {
                    TeamBadge(shortName: team.shortName, color: Palette.brand2, logoURL: team.logoUrl, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: team.name).font(AppFont.body(15, .semibold)).foregroundStyle(Palette.ink)
                        Text(verbatim: team.ownerName).font(AppFont.body(13)).foregroundStyle(Palette.ink3)
                    }
                } else {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.sunk))
                    Text("customTeam").font(AppFont.body(15, .semibold)).foregroundStyle(Palette.ink)
                }
            }
        }
    }
}
