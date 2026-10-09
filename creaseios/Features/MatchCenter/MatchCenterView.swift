import SwiftUI

struct MatchCenterView: View {
    let matchID: String
    @Environment(AppEnvironment.self) private var env
    @State private var model: MatchCenterModel?

    var body: some View {
        Group {
            if let model {
                MatchCenterContent(model: model)
            } else {
                SkeletonList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .smoothChange(model == nil)
        .screenBackground()
        .brandTitle("matchCentre")
        .clearNavBar()
        .task {
            let m = model ?? MatchCenterModel(matchID: matchID, env: env)
            model = m
            await m.watch()
        }
    }
}

private enum CenterTab: Hashable { case live, scorecard, squads }

private struct MatchCenterContent: View {
    let model: MatchCenterModel
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @State private var tab: CenterTab = .live

    var body: some View {
        Group {
            if model.notFound {
                MessageView(text: "errorNotFound", systemImage: "questionmark.circle")
            } else if let match = model.match {
                content(match)
            } else {
                SkeletonList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .smoothChange(model.match == nil)
        .smoothChange(model.notFound)
        .smoothChange(tab)
    }

    private func content(_ match: Match) -> some View {
        VStack(spacing: 0) {
            UnderlineTabs(tabs: [(.live, match.status == .completed ? "tabSummary" : "tabLive"),
                                 (.scorecard, "tabScorecard"),
                                 (.squads, "tabSquads")],
                          selection: $tab)
                
            ScrollView {
                VStack(spacing: 0) {
                    if tab == .live { LiveHero(match: match, state: model.state) }
                    VStack(spacing: 12) {
                        if match.status == .pending { pendingBanner(match) }
                        switch tab {
                        case .live: LiveTab(match: match, state: model.state)
                        case .scorecard: ScorecardTab(match: match, state: model.state)
                        case .squads: SquadsTab(match: match)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private func pendingBanner(_ match: Match) -> some View {
        if let uid = session.uid, match.pendingOwnerIds.contains(uid) {
            let team = [match.teamA, match.teamB].first { $0.ownerId == uid } ?? match.teamB
            VStack(alignment: .leading, spacing: 12) {
                Text("matchRequestBody \(team.name)").font(AppFont.body(15, .medium)).foregroundStyle(Palette.ink)
                HStack(spacing: 10) {
                    Button("decline") {
                        Task {
                            await model.decline()
                            router.goHome()
                        }
                    }
                    .secondaryButton()
                    Button("accept") { Task { await model.confirm(ownerID: uid) } }
                        .primaryButton()
                }
            }
            .card()
        } else {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").foregroundStyle(Palette.extra)
                Text("matchWaiting").font(AppFont.body(14, .medium)).foregroundStyle(Palette.ink2)
            }
            .card()
        }
    }
}

// MARK: - Shared

func dismissalText(_ b: BatterInnings, _ match: Match) -> String {
    if b.retiredNotOut { return "retired hurt" }
    guard b.isOut, let d = b.dismissal else { return b.isOut ? "out" : "not out" }
    let bowler = match.playerName(d.bowlerId)
    let fielder = match.playerName(d.fielderId)
    switch d.type {
    case .bowled: return "b \(bowler)"
    case .caught:
        if d.fielderId == nil { return "caught b \(bowler)" }
        return d.fielderId == d.bowlerId ? "c & b \(bowler)" : "c \(fielder) b \(bowler)"
    case .lbw: return "lbw b \(bowler)"
    case .stumped: return d.fielderId == nil ? "stumped b \(bowler)" : "st \(fielder) b \(bowler)"
    case .hitWicket: return "hit wicket b \(bowler)"
    case .runOut: return d.fielderId == nil ? "run out" : "run out (\(fielder))"
    case .retiredOut: return "retired out"
    case .obstructing: return "obstructing the field"
    }
}

private struct StatTable: View {
    let headers: [String]
    /// Width of each value column, after the name column.
    let widths: [CGFloat]
    let rows: [(id: String, name: String, sub: String?, values: [String])]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(verbatim: headers[0]).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(headers.dropFirst().enumerated()), id: \.offset) { i, h in
                    Text(verbatim: h).frame(width: widths[i], alignment: .trailing)
                }
            }
            .font(AppFont.body(12.5, .semibold))
            .foregroundStyle(Palette.ink3)
            .padding(.bottom, 4)
            ForEach(rows, id: \.id) { r in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: r.name).font(AppFont.body(16, .medium)).foregroundStyle(Palette.ink)
                        if let sub = r.sub { Text(verbatim: sub).font(AppFont.body(14)).foregroundStyle(Palette.ink3) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(r.values.enumerated()), id: \.offset) { i, v in
                        Text(verbatim: v)
                            .font(AppFont.mono(15, i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? Palette.ink : Palette.ink2)
                            .lineLimit(1)
                            .frame(width: widths[i], alignment: .trailing)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Live

/// Scores, status and run rates on the brand background, under the tabs.
private struct LiveHero: View {
    let match: Match
    let state: MatchState

    private var bpo: Int { match.config.ballsPerOver }

    var body: some View {
        let current = state.current
        VStack(alignment: .leading, spacing: 16) {
            ForEach([match.teamA, match.teamB], id: \.side) { team in
                teamRow(team, current: current)
            }
            if let current { statusLine(current) }
            if let current, !current.closed, match.status != .completed {
                HStack(spacing: 8) {
                    pill("CRR", current.runRate.twoDecimals)
                    if let rrr = requiredRate(current) { pill("RRR", rrr.twoDecimals) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.brand)
    }

    private func teamRow(_ team: MatchTeam, current: InningsState?) -> some View {
        let inn = state.innings.first { $0.battingTeam == team.side }
        let batting = current?.battingTeam == team.side && current?.closed == false && match.status != .completed
        return HStack(spacing: 12) {
            TeamBadge(shortName: team.shortName, color: team.uiColor, logoURL: team.logoUrl, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: team.name).font(AppFont.body(17, .medium)).foregroundStyle(Palette.onBrand).lineLimit(1)
                if batting {
                    Group {
                        if let target = inn?.target { Text("target \(target)") } else { Text("batting") }
                    }
                    .font(AppFont.body(14))
                    .foregroundStyle(Palette.onBrand2)
                }
            }
            Spacer(minLength: 8)
            if let inn {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(inn.runs)/\(inn.wickets)").font(AppFont.heading(batting ? 34 : 24, .heavy)).foregroundStyle(Palette.onBrand)
                    Text(verbatim: "\(inn.overs(bpo)) ov").font(AppFont.mono(13)).foregroundStyle(Palette.onBrand2)
                }
            } else {
                Text("yetToBat").font(AppFont.body(14)).foregroundStyle(Palette.onBrand2)
            }
        }
        .opacity(batting ? 1 : 0.6)
    }

    private func statusLine(_ inn: InningsState) -> some View {
        let team = match.team(inn.battingTeam)
        let completed = match.status == .completed
        return HStack(spacing: 8) {
            if !completed { PulsingDot(color: Palette.highlight) }
            Group {
                if completed, let result = match.displayResultText {
                    Text(verbatim: result)
                } else if let target = inn.target, !inn.closed {
                    let ballsLeft = match.config.oversPerInnings * bpo - inn.legalBalls
                    Text("needRunsInBalls \(team.shortName) \(max(0, target - inn.runs)) \(max(0, ballsLeft))")
                } else {
                    Text("teamBatting \(team.shortName) \(inn.runRate.twoDecimals)")
                }
            }
            .font(AppFont.body(15, .medium))
            .foregroundStyle(Palette.highlight)
        }
    }

    private func pill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: label).font(AppFont.body(13)).foregroundStyle(Palette.onBrand2)
            Text(verbatim: value).font(AppFont.mono(14, .semibold)).foregroundStyle(Palette.onBrand)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }

    private func requiredRate(_ inn: InningsState) -> Double? {
        guard let target = inn.target, !inn.closed else { return nil }
        let ballsLeft = match.config.oversPerInnings * bpo - inn.legalBalls
        guard ballsLeft > 0 else { return nil }
        return Double(target - inn.runs) / (Double(ballsLeft) / Double(bpo))
    }
}

private struct LiveTab: View {
    let match: Match
    let state: MatchState
    @Environment(\.locale) private var locale

    private var bpo: Int { match.config.ballsPerOver }
    private var completed: Bool { match.status == .completed }

    var body: some View {
        if let current = state.current {
            if !current.closed && !completed { creaseCard(current) }
            ForEach(state.innings, id: \.index) { inningsCard($0) }
            if completed { matchInfo }
        } else {
            MessageView(text: match.status == .live ? "waitingFirstBall" : "playNotStarted", systemImage: "clock")
        }
    }

    private func creaseCard(_ inn: InningsState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("atTheCrease").font(AppFont.body(17, .semibold)).foregroundStyle(Palette.ink)
            VStack(spacing: 0) {
                ForEach([inn.strikerId, inn.nonStrikerId].compactMap { $0 }, id: \.self) { id in
                    let b = inn.batters[id]
                    BatterLine(name: match.playerName(id), runs: b?.runs ?? 0, balls: b?.balls ?? 0, striker: id == inn.strikerId)
                }
                if let id = inn.currentBowlerId {
                    let s = inn.bowlers[id]
                    BowlerLine(name: match.playerName(id),
                               figures: "\(s?.overs(bpo) ?? "0.0")-\(s?.runsConceded ?? 0)-\(s?.wickets ?? 0)")
                        .padding(.top, 4)
                }
            }
            if !inn.currentOverBalls.isEmpty {
                HStack(spacing: 6) { ForEach(Array(inn.currentOverBalls.enumerated()), id: \.offset) { BallChip(token: $0.element) } }
                    .padding(.top, 6)
            }
        }
        .card(padding: 18)
    }

    private func inningsCard(_ inn: InningsState) -> some View {
        let team = match.team(inn.battingTeam)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TeamBadge(shortName: team.shortName, color: team.uiColor, logoURL: team.logoUrl, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: team.name).font(AppFont.body(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(verbatim: "\(inn.overs(bpo)) ov").font(AppFont.body(13)).foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(inn.runs)/\(inn.wickets)").font(AppFont.mono(17, .semibold)).foregroundStyle(Palette.ink)
            }
            if completed {
                Divider().overlay(Palette.line)
                performers("summaryTopBatters", topBatters(inn).map { b in
                    (b.playerId, "\(b.runs)\(b.isOut ? "" : "*")", "\(b.balls)b · \(b.fours)x4 · \(b.sixes)x6")
                })
                performers("summaryTopBowlers", topBowlers(inn).map { s in
                    (s.playerId, "\(s.wickets)/\(s.runsConceded)", "\(s.overs(bpo)) ov")
                })
            }
        }
        .card()
    }

    private var matchInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("summaryMatchInfo").font(AppFont.body(17, .semibold)).foregroundStyle(Palette.ink)
            if let toss = match.toss {
                let name = match.team(toss.winnerSide).name
                info("circle.lefthalf.filled", toss.decision == .bat ? Text("tossChoseBat \(name)") : Text("tossChoseBowl \(name)"))
            }
            info("sportscourt", Text(match.format.label) + Text(verbatim: " · \(match.config.oversPerInnings) overs"))
            if let venue = match.venueName { info("mappin.and.ellipse", Text(verbatim: venue)) }
            info("calendar", Text(verbatim: (match.scheduledDate ?? match.createdDate).formatted(.dateTime.day().month(.wide).year().locale(locale))))
        }
        .card()
    }

    private func topBatters(_ inn: InningsState) -> [BatterInnings] {
        inn.batters.values.filter(\.didBat).sorted { $0.runs != $1.runs ? $0.runs > $1.runs : $0.balls < $1.balls }.prefix(2).map { $0 }
    }

    private func topBowlers(_ inn: InningsState) -> [BowlerSpell] {
        inn.bowlers.values.sorted { $0.wickets != $1.wickets ? $0.wickets > $1.wickets : $0.runsConceded < $1.runsConceded }.prefix(2).map { $0 }
    }

    private func performers(_ title: LocalizedStringKey, _ rows: [(id: String, main: String, sub: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).textCase(.uppercase).font(AppFont.body(11.5, .semibold)).tracking(1).foregroundStyle(Palette.ink3)
            ForEach(rows, id: \.id) { r in
                HStack {
                    Text(verbatim: match.playerName(r.id)).font(AppFont.body(14.5, .medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: r.main).font(AppFont.mono(15, .semibold)).foregroundStyle(Palette.ink)
                        Text(verbatim: r.sub).font(AppFont.mono(11.5)).foregroundStyle(Palette.ink3)
                    }
                }
            }
        }
    }

    private func info(_ icon: String, _ text: Text) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Palette.ink3)
            text.font(AppFont.body(14)).foregroundStyle(Palette.ink2)
        }
    }
}

// MARK: - Scorecard

private struct ScorecardTab: View {
    let match: Match
    let state: MatchState
    @Environment(\.locale) private var locale

    private var bpo: Int { match.config.ballsPerOver }

    var body: some View {
        if state.innings.isEmpty {
            MessageView(text: "noOversYet", systemImage: "list.bullet.rectangle")
        }
        ForEach(state.innings, id: \.index) { inn in
            let team = match.team(inn.battingTeam)
            let batRuns = inn.batters.values.reduce(0) { $0 + $1.runs }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TeamBadge(shortName: team.shortName, color: team.uiColor, logoURL: team.logoUrl, size: 32)
                    Text(verbatim: team.name).font(AppFont.body(17, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(inn.runs)/\(inn.wickets)").font(AppFont.mono(16, .semibold)).foregroundStyle(Palette.ink)
                        Text(verbatim: "(\(inn.overs(bpo)))").font(AppFont.mono(13)).foregroundStyle(Palette.ink3)
                    }
                }
                StatTable(headers: [localized("batter", locale), "R", "B", "SR"], widths: [40, 40, 62],
                          rows: inn.battingOrder.compactMap { id in
                              guard let b = inn.batters[id], b.didBat || id == inn.strikerId || id == inn.nonStrikerId else { return nil }
                              return (id, match.playerName(id), dismissalText(b, match),
                                      ["\(b.runs)", "\(b.balls)", b.strikeRate.oneDecimal])
                          })
                HStack {
                    Text("extras").font(AppFont.body(16)).foregroundStyle(Palette.ink3)
                    Spacer()
                    Text(verbatim: "\(inn.runs - batRuns)").font(AppFont.mono(15, .semibold)).foregroundStyle(Palette.ink)
                }
            }
            .card(padding: 18)

            ExpandableCard(title: "bowling") {
                StatTable(headers: [localized("bowling", locale), "O", "M", "R", "W", "Econ"], widths: [40, 28, 34, 28, 54],
                          rows: inn.bowlers.values.sorted { $0.playerId < $1.playerId }.map { s in
                              (s.playerId, match.playerName(s.playerId), nil,
                               [s.overs(bpo), "\(s.maidens)", "\(s.runsConceded)", "\(s.wickets)", s.economy(bpo).twoDecimals])
                          })
            }
        }
    }
}

// MARK: - Squads

private struct SquadsTab: View {
    let match: Match
    @State private var side = "A"

    var body: some View {
        let team = match.team(side)
        PillSegments(tabs: [("A", match.teamA.name), ("B", match.teamB.name)], selection: $side)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                TeamBadge(shortName: team.shortName, color: team.uiColor, logoURL: team.logoUrl, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: team.name).font(AppFont.heading(18, .bold)).foregroundStyle(Palette.ink)
                    Text("playersCount \(team.squad.count)").font(AppFont.body(14)).foregroundStyle(Palette.ink3)
                }
            }
            .padding(.bottom, 8)
            ForEach(team.squad) { p in
                HStack(spacing: 14) {
                    PlayerAvatar(name: p.name, photoURL: p.photoUrl, size: 40, teamColor: team.uiColor, bordered: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: p.name).font(AppFont.body(16, .medium)).foregroundStyle(Palette.ink)
                        Text(p.role.label).font(AppFont.body(14)).foregroundStyle(Palette.ink3)
                    }
                    Spacer()
                    if p.id == team.captainId { tag("C") }
                    if p.id == team.wicketKeeperId { tag("WK") }
                }
                .padding(.vertical, 6)
            }
        }
        .card()
    }

    private func tag(_ text: String) -> some View {
        Text(verbatim: text)
            .font(AppFont.mono(11, .semibold))
            .foregroundStyle(Palette.onHighlight)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(Palette.highlight))
    }
}

#if DEBUG
@MainActor private func previewCentre(_ match: Match) -> some View {
    NavigationStack {
        MatchCenterContent(model: .preview(match))
            .screenBackground()
            .brandTitle("matchCentre")
            .clearNavBar()
    }
    .previewEnvironment()
}

#Preview("Match centre live") { previewCentre(.live) }

#Preview("Match centre completed") { previewCentre(.completed) }

#Preview("Match centre pending") { previewCentre(.pending) }

#Preview("Match centre loading") {
    NavigationStack { MatchCenterView(matchID: "live") }.previewEnvironment()
}

#Preview("Live hero") {
    ScrollView { LiveHero(match: .live, state: Match.live.sampleState) }
}

#Preview("Live tab") {
    ScrollView { VStack(spacing: 12) { LiveTab(match: .live, state: Match.live.sampleState) }.padding() }
        .screenBackground()
}

#Preview("Summary tab") {
    ScrollView { VStack(spacing: 12) { LiveTab(match: .completed, state: Match.completed.sampleState) }.padding() }
        .screenBackground()
}

#Preview("Scorecard tab") {
    ScrollView { VStack(spacing: 12) { ScorecardTab(match: .completed, state: Match.completed.sampleState) }.padding() }
        .screenBackground()
}

#Preview("Squads tab") {
    ScrollView { VStack(spacing: 12) { SquadsTab(match: .live) }.padding() }
        .screenBackground()
}

#Preview("Stat table") {
    StatTable(headers: ["Batter", "R", "B", "SR"], widths: [40, 40, 62],
              rows: [("1", "Kasun Perera", "b Akila Pathirana", ["42", "31", "135.5"]),
                     ("2", "Dilan Fernando", "not out", ["7", "12", "58.3"])])
        .card()
        .padding()
        .screenBackground()
}
#endif
