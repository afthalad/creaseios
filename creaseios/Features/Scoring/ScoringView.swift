import SwiftUI

struct ScoringView: View {
    let matchID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var model: ScoringModel?

    var body: some View {
        Group {
            if let model {
                ScoringContent(model: model)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .brandTitle("scoring") { router.pop() }
        .brandNavBar()
        .task {
            guard model == nil else { return }
            let m = ScoringModel(matchID: matchID, env: env)
            model = m
            await m.load()
        }
    }
}

private enum ScoringSheet: String, Identifiable {
    case openers, newBowler, extras, wicket, retire
    var id: String { rawValue }
}

private struct ScoringContent: View {
    @Bindable var model: ScoringModel
    @Environment(Router.self) private var router
    @State private var sheet: ScoringSheet?
    @State private var noteText = ""
    @State private var showNote = false
    @State private var confirmEnd = false

    var body: some View {
        Group {
            if model.notFound {
                MessageView(text: "errorNotFound", systemImage: "questionmark.circle")
            } else if model.match == nil {
                ProgressView()
            } else if model.isComplete {
                resultView
            } else {
                VStack(spacing: 0) {
                    if let inn = model.current, let match = model.match {
                        CreasePanel(match: match, innings: inn, bowlerID: model.bowlerID)
                    }
                    Spacer(minLength: 16)
                    scorePad.padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { router.push(.matchCenter(matchID: model.matchID)) } label: { Image(systemName: "list.bullet.clipboard") }
                Menu {
                    Button { router.goHome() } label: { Label("backToHome", systemImage: "house") }
                    if model.hasStarted && !model.isComplete {
                        Button(role: .destructive) { confirmEnd = true } label: { Label("endInnings", systemImage: "flag.checkered") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .withoutGlass()
        }
        .tint(Palette.onBrand)
        .sheet(item: sheetBinding) { s in
            Group {
                switch s {
                case .openers: OpenersSheet(model: model)
                case .newBowler: NewBowlerSheet(model: model)
                case .extras: ExtrasSheet(model: model)
                case .wicket: WicketSheet(model: model)
                case .retire: RetireSheet(model: model)
                }
            }
            .tint(Palette.btn)
            .presentationCornerRadius(22)
            .presentationDragIndicator(.visible)
        }
        .alert("note", isPresented: $showNote) {
            TextField("note", text: $noteText)
            Button("cancel", role: .cancel) {}
            Button("save") { Task { await model.addNote(noteText); noteText = "" } }
        }
        .alert("endInnings", isPresented: $confirmEnd) {
            Button("cancel", role: .cancel) {}
            Button("confirm", role: .destructive) { Task { await model.endInnings() } }
        }
    }

    private var sheetBinding: Binding<ScoringSheet?> {
        Binding(
            get: {
                switch model.prompt {
                case .openers: .openers
                case .newBowler: .newBowler
                case .none: sheet
                }
            },
            set: { sheet = $0 == .openers || $0 == .newBowler ? nil : $0 }
        )
    }

    private var scorePad: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(0..<4) { r in
                    padKey { Task { await model.runs(r) } } label: {
                        Text(verbatim: "\(r)").font(AppFont.mono(26, .semibold)).foregroundStyle(Palette.ink)
                    }
                    .aspectRatio(1.4, contentMode: .fit)
                }
            }
            HStack(spacing: 8) {
                padKey { Task { await model.runs(4) } } label: {
                    Text(verbatim: "4").font(AppFont.mono(28, .bold)).foregroundStyle(Palette.four)
                }
                .frame(height: 62)
                padKey(fill: Palette.btn) { Task { await model.runs(6) } } label: {
                    Text(verbatim: "6").font(AppFont.mono(28, .bold)).foregroundStyle(.white)
                }
                .frame(height: 62)
            }
            GeometryReader { geo in
                let unit = (geo.size.width - 8) / 3
                HStack(spacing: 8) {
                    padKey { sheet = .extras } label: {
                        Text("extra").textCase(.uppercase).font(AppFont.body(15, .bold)).tracking(1.5).foregroundStyle(Palette.extra)
                    }
                    .frame(width: unit)
                    padKey(fill: Palette.wkt) { sheet = .wicket } label: {
                        Text("wicket").textCase(.uppercase).font(AppFont.body(15, .bold)).tracking(1.5).foregroundStyle(.white)
                    }
                    .frame(width: unit * 2)
                }
            }
            .frame(height: 56)
            HStack(spacing: 8) {
                smallKey("undo", "arrow.uturn.backward", enabled: model.canUndo) { Task { await model.undo() } }
                smallKey("swap", "arrow.left.arrow.right", enabled: model.hasStarted) { Task { await model.swapEnds() } }
                smallKey("retire", "flag", enabled: model.hasStarted) { sheet = .retire }
                smallKey("note", "square.and.pencil") { showNote = true }
            }
        }
        .disabled(model.busy || model.prompt != .none)
    }

    private func padKey<L: View>(fill: Color = Palette.surface, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(fill))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        }
        .buttonStyle(PadButtonStyle())
    }

    private func smallKey(_ title: LocalizedStringKey, _ icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(AppFont.body(14, .medium))
            }
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PadButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill").font(.system(size: 44)).foregroundStyle(Palette.accent)
            Text("matchComplete").font(AppFont.heading(24, .heavy)).foregroundStyle(Palette.ink)
            Text(verbatim: model.match?.displayResultText ?? "")
                .font(AppFont.body(17, .semibold))
                .foregroundStyle(Palette.six)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button("viewScorecard") { router.push(.matchCenter(matchID: model.matchID)) }.primaryButton()
                Button("backToHome") { router.goHome() }.secondaryButton()
                Button { Task { await model.undo() } } label: { Label("undo", systemImage: "arrow.uturn.backward") }
                    .font(AppFont.body(14, .medium))
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 4)
            }
            .padding(.top, 12)
        }
        .padding(32)
    }
}

private struct PadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CreasePanel: View {
    let match: Match
    let innings: InningsState
    let bowlerID: String?

    private var bpo: Int { match.config.ballsPerOver }

    var body: some View {
        VStack(spacing: 0) {
            header
            if innings.strikerId != nil || bowlerID != nil { creaseStrip }
        }
    }

    private var creaseStrip: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                batterRow(innings.strikerId, striker: true)
                batterRow(innings.nonStrikerId, striker: false)
            }
            .padding(.vertical, 6)
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 4) {
                if let id = bowlerID {
                    let spell = innings.bowlers[id]
                    BowlerLine(name: match.playerName(id),
                               figures: "\(spell?.overs(bpo) ?? "0.0")-\(spell?.runsConceded ?? 0)-\(spell?.wickets ?? 0)")
                }
                if !innings.currentOverBalls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(innings.currentOverBalls.enumerated()), id: \.offset) { BallChip(token: $0.element) }
                        }
                        .padding(.leading, 18)
                    }
                    .padding(.bottom, 6)
                }
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 16)
        .background(Palette.surface)
    }

    private var header: some View {
        let team = match.team(innings.battingTeam)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: team.name).font(AppFont.body(16)).foregroundStyle(Palette.onBrand2)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(innings.runs)/\(innings.wickets)").font(AppFont.heading(52, .heavy)).foregroundStyle(Palette.onBrand)
                Text(verbatim: "(\(innings.overs(bpo)) ov)").font(AppFont.mono(17)).foregroundStyle(Palette.onBrand2)
            }
            HStack(spacing: 16) {
                meta("CRR", innings.runRate.twoDecimals)
                if let target = innings.target {
                    meta(localizedKey: "targetLabel", "\(target)")
                    meta(localizedKey: "need", "\(max(0, target - innings.runs))")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brand)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: label).font(AppFont.body(14)).foregroundStyle(Palette.onBrand2)
            Text(verbatim: value).font(AppFont.mono(15, .semibold)).foregroundStyle(Palette.onBrand)
        }
    }

    private func meta(localizedKey: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(localizedKey).font(AppFont.body(14)).foregroundStyle(Palette.onBrand2)
            Text(verbatim: value).font(AppFont.mono(15, .semibold)).foregroundStyle(Palette.accent)
        }
    }

    @ViewBuilder
    private func batterRow(_ id: String?, striker: Bool) -> some View {
        if let id {
            let b = innings.batters[id]
            BatterLine(name: match.playerName(id), runs: b?.runs ?? 0, balls: b?.balls ?? 0, striker: striker)
        }
    }
}
