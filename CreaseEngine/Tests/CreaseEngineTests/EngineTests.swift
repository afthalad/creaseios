import Foundation
import Testing
@testable import CreaseEngine

private struct Fixture: Decodable {
    struct Expected: Decodable {
        struct Inn: Decodable { let runs: Int; let wickets: Int; let closed: Bool; let endReason: String? }
        struct Res: Decodable { let type: String; let winner: String?; let text: String }
        let innings: [Inn]
        let result: Res
    }
    let config: MatchConfig
    let inningsBattingTeam: [String]
    let events: [MatchEvent]
    let expected: Expected
}

private let engine = CreaseEngine()
private let config = MatchConfig(oversPerInnings: 2, playersPerSide: 3)

private func ball(_ seq: Int, _ s: String, _ ns: String, _ b: String, inn: Int = 0,
                  _ fill: (inout BallEvent) -> Void = { _ in }) -> MatchEvent {
    var e = BallEvent(strikerId: s, nonStrikerId: ns, bowlerId: b)
    fill(&e)
    return MatchEvent(seq: seq, inningsIndex: inn, kind: .ball(e))
}

@Test(arguments: ["simple_result", "extras_and_tie"])
func goldenFixture(name: String) throws {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    let f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    let s = engine.replay(events: f.events, config: f.config, inningsBattingTeam: f.inningsBattingTeam)
    #expect(s.innings.count == f.expected.innings.count)
    for (i, e) in f.expected.innings.enumerated() {
        #expect(s.innings[i].runs == e.runs)
        #expect(s.innings[i].wickets == e.wickets)
        #expect(s.innings[i].closed == e.closed)
        #expect(s.innings[i].endReason == e.endReason)
    }
    #expect(s.result?.type.rawValue == f.expected.result.type)
    #expect(s.result?.winner == f.expected.result.winner)
    #expect(s.result?.text == f.expected.result.text)
}

@Test func voidUndoesAWicket() {
    let events = [
        ball(1, "a1", "a2", "b1") { $0.runsOffBat = 2 },
        ball(2, "a1", "a2", "b1") { $0.dismissal = Dismissal(type: .bowled, bowlerId: "b1"); $0.dismissedPlayerId = "a1"; $0.incomingBatterId = "a3" },
        MatchEvent(seq: 3, inningsIndex: 0, kind: .void(seq: 2)),
    ]
    let inn = engine.replay(events: events, config: config, inningsBattingTeam: ["A", "B"]).innings[0]
    #expect(inn.wickets == 0)
    #expect(inn.strikerId == "a1")
    #expect(inn.bowlers["b1"]?.wickets == 0)
    #expect(inn.batters["a1"]?.isOut == false)
}

@Test func noBallRunsGoToBatter() {
    let inn = engine.replay(events: [ball(1, "a1", "a2", "b1") { $0.extra = .noBall; $0.runsOffBat = 4 }],
                            config: config, inningsBattingTeam: ["A", "B"]).innings[0]
    #expect(inn.runs == 5)
    #expect(inn.legalBalls == 0)
    #expect(inn.batters["a1"]?.runs == 4)
    #expect(inn.batters["a1"]?.balls == 0)
    #expect(inn.bowlers["b1"]?.runsConceded == 5)
}

@Test func oddByesRotateStrikeAndMaidenCounts() {
    let events = (1...6).map { i in
        ball(i, i % 2 == 1 ? "a1" : "a2", i % 2 == 1 ? "a2" : "a1", "b1") { $0.extra = .bye; $0.extraRuns = 1 }
    }
    let inn = engine.replay(events: events, config: config, inningsBattingTeam: ["A", "B"]).innings[0]
    #expect(inn.runs == 6)
    #expect(inn.bowlers["b1"]?.maidens == 1)
    #expect(inn.strikerId == "a2")
    #expect(inn.overHistory.first == ["b1", "b1", "b1", "b1", "b1", "b1"])
}

@Test func secondInningsTargetAndAllOut() {
    let events = [
        ball(1, "a1", "a2", "b1") { $0.runsOffBat = 6 },
        MatchEvent(seq: 2, inningsIndex: 0, kind: .inningsEnd(reason: "declared")),
        ball(3, "c1", "c2", "a1", inn: 1) { $0.dismissal = Dismissal(type: .lbw, bowlerId: "a1"); $0.dismissedPlayerId = "c1"; $0.incomingBatterId = "c3" },
        ball(4, "c3", "c2", "a1", inn: 1) { $0.dismissal = Dismissal(type: .caught, bowlerId: "a1", fielderId: "a2"); $0.dismissedPlayerId = "c3" },
    ]
    let s = engine.replay(events: events, config: config, inningsBattingTeam: ["A", "B"])
    #expect(s.innings[1].target == 7)
    #expect(s.innings[1].endReason == "all out")
    #expect(s.result?.text == "Team A won by 6 runs")
}
