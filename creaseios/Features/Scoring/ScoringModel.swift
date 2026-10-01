import SwiftUI
import CreaseEngine

@MainActor @Observable
final class ScoringModel {
    enum Prompt { case none, openers, newBowler }

    private(set) var match: Match?
    private(set) var state = MatchState()
    private(set) var prompt: Prompt = .none
    private(set) var notFound = false
    private(set) var busy = false
    private var events: [MatchEvent] = []
    private var seq = 0
    private var openerStriker: String?
    private var openerNonStriker: String?
    private var nextBowler: String?

    let matchID: String
    let env: AppEnvironment

    init(matchID: String, env: AppEnvironment) {
        self.matchID = matchID
        self.env = env
    }

    /// 0 or 1 while play is on, 2 once both innings are closed.
    var targetIndex: Int {
        guard let last = state.innings.last else { return 0 }
        return last.closed ? last.index + 1 : last.index
    }
    var isComplete: Bool { targetIndex >= 2 }
    var canUndo: Bool { events.contains { !$0.isVoid } && !busy }
    var hasStarted: Bool { scoringInnings != nil }
    var config: MatchConfig? { match?.config }

    private var scoringInnings: InningsState? { state.innings.first { $0.index == targetIndex } }

    /// The innings being scored, or a placeholder carrying the chosen openers before ball one.
    var current: InningsState? {
        if let i = scoringInnings { return i }
        guard let match, !isComplete else { return nil }
        let bat = match.inningsBattingOrder[targetIndex]
        var i = InningsState(index: targetIndex, battingTeam: bat, bowlingTeam: bat == "A" ? "B" : "A",
                             target: targetIndex == 1 ? state.innings.first.map { $0.runs + 1 } : nil)
        i.strikerId = openerStriker
        i.nonStrikerId = openerNonStriker
        i.currentBowlerId = nextBowler
        return i
    }

    var bowlerID: String? { nextBowler ?? scoringInnings?.currentBowlerId }

    var battingTeam: MatchTeam? { current.flatMap { match?.team($0.battingTeam) } }
    var bowlingTeam: MatchTeam? { current.flatMap { match?.team($0.bowlingTeam) } }

    /// Batters who can still come in: not out, not at the crease.
    var availableBatters: [Player] {
        guard let inn = current, let team = battingTeam else { return [] }
        return team.squad.filter { p in
            p.id != inn.strikerId && p.id != inn.nonStrikerId && inn.batters[p.id]?.isOut != true
        }
    }

    var previousOverBowler: String? {
        guard let inn = scoringInnings, inn.legalBalls > 0, inn.currentOverBalls.isEmpty else { return nil }
        return inn.currentBowlerId
    }

    func load() async {
        guard let m = try? await env.matches.getMatch(matchID) else { notFound = true; return }
        match = m
        events = (try? await env.matches.loadEvents(matchID)) ?? []
        seq = events.map(\.seq).max() ?? 0
        rebuild()
    }

    private func rebuild() {
        guard let match else { return }
        state = env.engine.replay(events: events, config: match.config, inningsBattingTeam: match.inningsBattingOrder)
        let t = scoringInnings
        if isComplete {
            prompt = .none
        } else if t?.strikerId == nil {
            prompt = openerStriker != nil && openerNonStriker != nil && nextBowler != nil ? .none : .openers
        } else if let t, t.legalBalls > 0, t.legalBalls % match.config.ballsPerOver == 0,
                  t.currentOverBalls.isEmpty, nextBowler == nil {
            prompt = .newBowler
        } else {
            prompt = .none
        }
    }

    func confirmOpeners(striker: String, nonStriker: String, bowler: String) {
        openerStriker = striker
        openerNonStriker = nonStriker
        nextBowler = bowler
        rebuild()
    }

    func confirmBowler(_ id: String) {
        nextBowler = id
        rebuild()
    }

    /// True when this wicket would end the innings, so no next batter is needed.
    func wicketEndsInnings(runs: Int = 0) -> Bool {
        guard let inn = current, let c = config else { return true }
        if inn.wickets + 1 >= c.playersPerSide - 1 { return true }
        if c.isLimitedOvers && inn.legalBalls + 1 >= c.oversPerInnings * c.ballsPerOver { return true }
        if let t = inn.target, inn.runs + runs >= t { return true }
        return false
    }

    func runs(_ r: Int) async { await ball { $0.runsOffBat = r } }

    func extra(_ type: ExtraType, runs: Int) async {
        await ball {
            $0.extra = type
            if type == .noBall { $0.runsOffBat = runs } else { $0.extraRuns = runs }
        }
    }

    func wicket(_ d: Dismissal, out: String, incoming: String?, runsBefore: Int) async {
        await ball {
            $0.runsOffBat = runsBefore
            $0.dismissal = d
            $0.dismissedPlayerId = out
            $0.incomingBatterId = incoming
        }
    }

    func swapEnds() async {
        guard let inn = scoringInnings, !inn.closed else { return }
        await next(.swap)
    }

    func retire(_ outgoing: String, incoming: String, isOut: Bool) async {
        guard scoringInnings != nil else { return }
        await next(.retire(outgoing: outgoing, incoming: incoming, isOut: isOut))
    }

    func addNote(_ text: String) async {
        guard !text.trimmed.isEmpty else { return }
        await next(.note(text.trimmed))
    }

    func endInnings() async {
        guard scoringInnings != nil, !isComplete else { return }
        await next(.inningsEnd(reason: "declared"))
    }

    func addPlayer(_ name: String, side: String) -> Player? {
        guard var m = match, !name.trimmed.isEmpty else { return nil }
        let p = Player(id: UUID().uuidString.lowercased(), name: name.trimmed)
        if side == "A" { m.teamA.squad.append(p) } else { m.teamB.squad.append(p) }
        try? env.matches.update(m)
        match = m
        return p
    }

    func undo() async {
        let voided = Set(events.compactMap { e -> Int? in
            if case .void(let s) = e.kind { return s }
            return nil
        })
        guard let target = events.reversed().first(where: { !$0.isVoid && !voided.contains($0.seq) }) else { return }
        await append(.void(seq: target.seq), inningsIndex: target.inningsIndex)
    }

    private func ball(_ fill: (inout BallEvent) -> Void) async {
        guard !isComplete else { return }
        let t = scoringInnings
        guard let striker = t?.strikerId ?? openerStriker,
              let nonStriker = t?.nonStrikerId ?? openerNonStriker,
              let bowler = nextBowler ?? t?.currentBowlerId else { return }
        var b = BallEvent(strikerId: striker, nonStrikerId: nonStriker, bowlerId: bowler)
        fill(&b)
        nextBowler = nil
        openerStriker = nil
        openerNonStriker = nil
        await next(.ball(b))
    }

    private func next(_ kind: EventKind) async {
        await append(kind, inningsIndex: targetIndex)
    }

    private func append(_ kind: EventKind, inningsIndex: Int) async {
        guard var m = match, !busy else { return }
        busy = true
        defer { busy = false }
        seq += 1
        let e = MatchEvent(seq: seq, inningsIndex: inningsIndex, kind: kind)
        do {
            try env.matches.append(matchID, e)
        } catch {
            seq -= 1
            rebuild()
            return
        }
        events.append(e)
        rebuild()

        let scores = Dictionary(state.innings.map {
            ($0.battingTeam, TeamScore(runs: $0.runs, wickets: $0.wickets, balls: $0.legalBalls))
        }, uniquingKeysWith: { $1 })
        let batting = state.current?.battingTeam
        let finished = state.result != nil
        let status: MatchStatus = finished ? .completed : .live
        guard status != m.status || scores != m.scores || batting != m.battingSide else { return }
        m.scores = scores
        m.battingSide = batting
        m.status = status
        m.resultText = state.result?.text
        m.winnerSide = state.result?.winner
        try? env.matches.update(m)
        match = m
    }
}
