import SwiftUI

/// A list of players to choose from, with an inline field to add someone missing from the squad.
struct PlayerPickList: View {
    let title: LocalizedStringKey
    let players: [Player]
    var teamColor: Color? = nil
    var selected: String? = nil
    var onAdd: ((String) -> Void)? = nil
    let onPick: (Player) -> Void
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(title: title)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(players) { p in
                        Button { onPick(p) } label: {
                            HStack(spacing: 16) {
                                PlayerAvatar(name: p.name, photoURL: p.photoUrl, size: 36, highlighted: p.id == selected,
                                             teamColor: teamColor, bordered: true)
                                Text(verbatim: p.name).font(AppFont.body(17)).foregroundStyle(Palette.ink)
                                Spacer()
                                if p.id == selected { Image(systemName: "checkmark").foregroundStyle(Palette.six) }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let onAdd {
                        HStack(spacing: 8) {
                            TextField("playerName", text: $newName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .fieldStyle()
                            Button {
                                onAdd(newName)
                                newName = ""
                            } label: {
                                Image(systemName: "plus").fontWeight(.bold).foregroundStyle(Palette.onHighlight)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.highlight)
                            .controlSize(.large)
                            .disabled(newName.trimmed.isEmpty)
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }
}

struct OpenersSheet: View {
    let model: ScoringModel
    @State private var striker: Player?
    @State private var nonStriker: Player?

    var body: some View {
        let bat = model.battingTeam
        let bowl = model.bowlingTeam
        Group {
            if striker == nil {
                PlayerPickList(title: "openersStriker", players: bat?.squad ?? [], teamColor: bat?.uiColor,
                               onAdd: add(to: bat)) { striker = $0 }
            } else if nonStriker == nil {
                PlayerPickList(title: "openersNonStriker", players: (bat?.squad ?? []).filter { $0.id != striker?.id },
                               teamColor: bat?.uiColor, onAdd: add(to: bat)) { nonStriker = $0 }
            } else {
                PlayerPickList(title: "openersBowler", players: bowl?.squad ?? [], teamColor: bowl?.uiColor,
                               onAdd: add(to: bowl)) { p in
                    if let s = striker, let ns = nonStriker { model.confirmOpeners(striker: s.id, nonStriker: ns.id, bowler: p.id) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .animation(.easeInOut(duration: 0.2), value: striker)
        .animation(.easeInOut(duration: 0.2), value: nonStriker)
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }

    private func add(to team: MatchTeam?) -> (String) -> Void {
        { name in if let side = team?.side { _ = model.addPlayer(name, side: side) } }
    }
}

struct NewBowlerSheet: View {
    let model: ScoringModel

    var body: some View {
        let team = model.bowlingTeam
        PlayerPickList(title: "nextOverBowler",
                       players: (team?.squad ?? []).filter { $0.id != model.previousOverBowler },
                       teamColor: team?.uiColor,
                       onAdd: { name in if let side = team?.side { _ = model.addPlayer(name, side: side) } }) { p in
            model.confirmBowler(p.id)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }
}

private struct RunChips: View {
    let options: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { r in
                Button { selection = r } label: {
                    Text(verbatim: "\(r)")
                        .font(AppFont.mono(17, .semibold))
                        .foregroundStyle(selection == r ? Palette.onBrand : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(selection == r ? Palette.brand : Palette.sunk))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct Label13: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(AppFont.body(13, .semibold)).foregroundStyle(Palette.ink3)
    }
}

struct ExtrasSheet: View {
    let model: ScoringModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: ExtraType = .wide
    @State private var runs = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(title: "extras")
            FlowLayout {
                ForEach(ExtraType.allCases, id: \.self) { t in
                    ChoiceChip(title: t.label, selected: type == t) { type = t }
                }
            }
            Label13(text: type == .noBall ? "runsOffBat" : "additionalRuns")
            RunChips(options: [0, 1, 2, 3, 4, 6], selection: $runs)
            Spacer(minLength: 0)
            Button("confirm") {
                Task { await model.extra(type, runs: runs) }
                dismiss()
            }
            .primaryButton()
        }
        .padding(24)
        .presentationDetents([.height(340)])
    }
}

struct WicketSheet: View {
    let model: ScoringModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: DismissalType = .bowled
    @State private var outIsStriker = true
    @State private var runsCompleted = 0
    @State private var fielder: Player?
    @State private var pickingFielder = false
    @State private var pickingBatter = false

    private var inn: InningsState? { model.current }
    private var outID: String? { outIsStriker ? inn?.strikerId : inn?.nonStrikerId }
    private var canConfirm: Bool { !type.needsFielder || fielder != nil }

    var body: some View {
        Group {
            if pickingFielder {
                PlayerPickList(title: type == .stumped ? "wicketkeeper" : "selectFielder",
                               players: model.bowlingTeam?.squad ?? [], teamColor: model.bowlingTeam?.uiColor,
                               selected: fielder?.id) { p in
                    fielder = p
                    pickingFielder = false
                }
            } else if pickingBatter {
                PlayerPickList(title: "nextBatter", players: model.availableBatters, teamColor: model.battingTeam?.uiColor,
                               onAdd: { name in if let side = model.battingTeam?.side { _ = model.addPlayer(name, side: side) } }) { p in
                    commit(incoming: p.id)
                }
            } else {
                details
            }
        }
        .padding(24)
        .presentationDetents([.large])
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(title: "wicket")
            FlowLayout {
                ForEach(DismissalType.allCases, id: \.self) { t in
                    ChoiceChip(title: t.label, selected: type == t) {
                        type = t
                        if !t.needsFielder { fielder = nil }
                        if t != .runOut { runsCompleted = 0 }
                    }
                }
            }
            Label13(text: "whoIsOut")
            Picker("whoIsOut", selection: $outIsStriker) {
                Text("striker").tag(true)
                Text("nonStriker").tag(false)
            }
            .pickerStyle(.segmented)

            if type == .runOut {
                Label13(text: "runsCompleted")
                RunChips(options: [0, 1, 2, 3], selection: $runsCompleted)
            }

            if type.needsFielder {
                Button { pickingFielder = true } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        if let fielder { Text(verbatim: fielder.name) }
                        else { Text(type == .stumped ? "wicketkeeper" : "fielder") }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.ink3)
                    }
                    .font(AppFont.body(15, .medium))
                    .foregroundStyle(Palette.ink)
                    .fieldStyle()
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button("confirm") {
                if model.wicketEndsInnings(runs: runsCompleted) {
                    commit(incoming: nil)
                } else {
                    pickingBatter = true
                }
            }
            .primaryButton(tint: Palette.wicket)
            .disabled(!canConfirm || outID == nil)
        }
    }

    private func commit(incoming: String?) {
        guard let outID else { return }
        let d = Dismissal(type: type, bowlerId: type.creditsBowler ? model.bowlerID : nil, fielderId: fielder?.id)
        let runs = type == .runOut ? runsCompleted : 0
        Task { await model.wicket(d, out: outID, incoming: incoming, runsBefore: runs) }
        dismiss()
    }
}

struct RetireSheet: View {
    let model: ScoringModel
    @Environment(\.dismiss) private var dismiss
    @State private var outgoing: String?
    @State private var isOut = false

    var body: some View {
        Group {
            if let outgoing {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("retire", selection: $isOut) {
                        Text("retiredHurt").tag(false)
                        Text("dismissalRetiredOut").tag(true)
                    }
                    .pickerStyle(.segmented)
                    PlayerPickList(title: "nextBatter", players: model.availableBatters, teamColor: model.battingTeam?.uiColor,
                                   onAdd: { name in if let side = model.battingTeam?.side { _ = model.addPlayer(name, side: side) } }) { p in
                        Task { await model.retire(outgoing, incoming: p.id, isOut: isOut) }
                        dismiss()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SheetTitle(title: "retire")
                    ForEach([model.current?.strikerId, model.current?.nonStrikerId].compactMap { $0 }, id: \.self) { id in
                        Button { outgoing = id } label: {
                            HStack(spacing: 12) {
                                PlayerAvatar(name: model.match?.playerName(id) ?? "", size: 36, teamColor: model.battingTeam?.uiColor)
                                Text(verbatim: model.match?.playerName(id) ?? "").font(AppFont.body(15, .medium)).foregroundStyle(Palette.ink)
                                Spacer()
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
@MainActor private func previewSheet<S: View>(@ViewBuilder _ sheet: @escaping () -> S) -> some View {
    Color.clear.sheet(isPresented: .constant(true), content: sheet).previewEnvironment()
}

#Preview("Player pick list") {
    PlayerPickList(title: "nextBatter", players: MatchTeam.sampleA.squad, teamColor: MatchTeam.sampleA.uiColor,
                   selected: "kasun", onAdd: { _ in }) { _ in }
        .padding()
}

#Preview("Openers sheet") { previewSheet { OpenersSheet(model: .preview(.upcoming)) } }

#Preview("New bowler sheet") { previewSheet { NewBowlerSheet(model: .preview(.live)) } }

#Preview("Run chips") {
    @Previewable @State var runs = 1
    RunChips(options: [0, 1, 2, 3, 4, 6], selection: $runs).padding()
}

#Preview("Label") { Label13(text: "runsOffBat").padding() }

#Preview("Extras sheet") { previewSheet { ExtrasSheet(model: .preview(.live)) } }

#Preview("Wicket sheet") { previewSheet { WicketSheet(model: .preview(.live)) } }

#Preview("Retire sheet") { previewSheet { RetireSheet(model: .preview(.live)) } }
#endif
