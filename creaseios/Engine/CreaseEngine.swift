import Foundation

/// Rebuilds match state by folding the append-only event log. Same events in, same state out.
struct CreaseEngine: Sendable {
    init() {}

    func replay(events: [MatchEvent], config: MatchConfig, inningsBattingTeam: [String]) -> MatchState {
        let voided = Set(events.compactMap { e -> Int? in
            if case .void(let s) = e.kind { return s }
            return nil
        })
        var builders: [Int: InningsBuilder] = [:]
        var notes: [String] = []
        var current = 0

        for e in events.sorted(by: { $0.seq < $1.seq }) where !voided.contains(e.seq) && !e.isVoid {
            guard e.inningsIndex == 0 || e.inningsIndex == 1 else { continue }
            if builders[e.inningsIndex] == nil {
                let target = e.inningsIndex == 1 ? builders[0].map { $0.state.runs + 1 } : nil
                builders[e.inningsIndex] = InningsBuilder(
                    index: e.inningsIndex,
                    battingTeam: inningsBattingTeam[e.inningsIndex],
                    bowlingTeam: inningsBattingTeam[1 - e.inningsIndex],
                    ballsPerOver: config.ballsPerOver,
                    target: target)
            }
            current = e.inningsIndex
            var b = builders[e.inningsIndex]!

            switch e.kind {
            case .ball(let ball): b.apply(ball)
            case .retire(let o, let i, let out): b.retire(outgoing: o, incoming: i, isOut: out)
            case .swap: b.swapEnds()
            case .note(let text): notes.append(text)
            case .inningsEnd(let reason): b.close(reason)
            case .void: break
            }
            if !b.state.closed { autoClose(&b, config) }
            builders[e.inningsIndex] = b
        }

        let innings = builders.values.map(\.state).sorted { $0.index < $1.index }
        var state = MatchState(currentInningsIndex: current, innings: innings, notes: notes)
        state.result = result(state, config)
        return state
    }

    private func autoClose(_ b: inout InningsBuilder, _ c: MatchConfig) {
        let s = b.state
        if s.wickets >= c.playersPerSide - 1 {
            b.close("all out")
        } else if let t = s.target, s.runs >= t {
            b.close("target reached")
        } else if c.isLimitedOvers && s.legalBalls >= c.oversPerInnings * c.ballsPerOver {
            b.close("overs completed")
        }
    }

    func result(_ s: MatchState, _ c: MatchConfig) -> MatchResult? {
        guard s.innings.count >= 2, s.innings[0].closed, s.innings[1].closed else { return nil }
        let first = s.innings[0], second = s.innings[1]
        if first.runs == second.runs {
            return MatchResult(type: .tie, winner: nil, text: "Match tied")
        }
        if second.runs > first.runs {
            let w = c.playersPerSide - 1 - second.wickets
            return MatchResult(type: .win, winner: second.battingTeam,
                               text: "Team \(second.battingTeam) won by \(w) wicket\(w == 1 ? "" : "s")")
        }
        let m = first.runs - second.runs
        return MatchResult(type: .win, winner: first.battingTeam,
                           text: "Team \(first.battingTeam) won by \(m) run\(m == 1 ? "" : "s")")
    }
}

struct InningsBuilder {
    var state: InningsState
    let ballsPerOver: Int
    private var overBowlerRuns = 0

    init(index: Int, battingTeam: String, bowlingTeam: String, ballsPerOver: Int, target: Int?) {
        state = InningsState(index: index, battingTeam: battingTeam, bowlingTeam: bowlingTeam, target: target)
        self.ballsPerOver = ballsPerOver
    }

    private mutating func addBatter(_ id: String) {
        guard state.batters[id] == nil else { return }
        state.batters[id] = BatterInnings(playerId: id)
        state.battingOrder.append(id)
    }

    private mutating func addBowler(_ id: String) {
        if state.bowlers[id] == nil { state.bowlers[id] = BowlerSpell(playerId: id) }
    }

    private mutating func rotate() { swap(&state.strikerId, &state.nonStrikerId) }

    mutating func swapEnds() { if !state.closed { rotate() } }

    mutating func close(_ reason: String) {
        state.closed = true
        state.endReason = reason
    }

    mutating func apply(_ e: BallEvent) {
        guard !state.closed else { return }
        state.strikerId = e.strikerId
        state.nonStrikerId = e.nonStrikerId
        state.currentBowlerId = e.bowlerId
        addBatter(e.strikerId)
        addBatter(e.nonStrikerId)
        addBowler(e.bowlerId)
        state.runs += e.battingTeamRuns

        var striker = state.batters[e.strikerId]!
        if e.extra == nil || e.extra == .bye || e.extra == .legBye { striker.balls += 1 }
        if e.extra == nil || (e.extra == .noBall && e.runsOffBat > 0) {
            striker.runs += e.runsOffBat
            if e.runsOffBat == 4 { striker.fours += 1 }
            if e.runsOffBat == 6 { striker.sixes += 1 }
        }
        state.batters[e.strikerId] = striker

        state.bowlers[e.bowlerId]!.runsConceded += e.bowlerConcededRuns
        if e.isLegal {
            state.bowlers[e.bowlerId]!.legalBalls += 1
            state.legalBalls += 1
        }
        overBowlerRuns += e.bowlerConcededRuns
        state.currentOverBalls.append(token(e))

        if e.runsForStrikeRotation % 2 == 1 { rotate() }

        if let d = e.dismissal, let outId = e.dismissedPlayerId {
            state.batters[outId]?.isOut = true
            state.batters[outId]?.dismissal = d
            state.wickets += 1
            if d.type.creditsBowler { state.bowlers[e.bowlerId]!.wickets += 1 }
            if let incoming = e.incomingBatterId {
                if state.strikerId == outId { state.strikerId = incoming }
                else if state.nonStrikerId == outId { state.nonStrikerId = incoming }
                addBatter(incoming)
            }
        }

        if e.isLegal && state.legalBalls % ballsPerOver == 0 {
            state.overHistory.append(state.currentOverBalls)
            state.currentOverBalls = []
            if overBowlerRuns == 0 { state.bowlers[e.bowlerId]!.maidens += 1 }
            overBowlerRuns = 0
            rotate()
        }
    }

    mutating func retire(outgoing: String, incoming: String, isOut: Bool) {
        guard !state.closed else { return }
        if state.batters[outgoing] != nil {
            state.batters[outgoing]!.retiredNotOut = !isOut
            state.batters[outgoing]!.isOut = isOut
        }
        addBatter(incoming)
        if state.strikerId == outgoing { state.strikerId = incoming }
        if state.nonStrikerId == outgoing { state.nonStrikerId = incoming }
    }

    private func token(_ e: BallEvent) -> String {
        if e.dismissal != nil { return "W" }
        switch e.extra {
        case .wide: return e.extraRuns > 0 ? "wd+\(e.extraRuns)" : "wd"
        case .noBall: return e.runsOffBat > 0 ? "nb+\(e.runsOffBat)" : "nb"
        case .bye: return "b\(e.extraRuns)"
        case .legBye: return "lb\(e.extraRuns)"
        case nil: return "\(e.runsOffBat)"
        }
    }
}
