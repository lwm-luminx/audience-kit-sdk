import Foundation
import Testing
@testable import ArbiterControl

@Suite("arbiterctl judge")
struct VectorJudgeTests {
    @Test func parsesTheJudgeCommand() throws {
        #expect(try ControlCommandLine.parse(["judge", "-m", "gemma.gguf", "-o", "arbiter.jsonl", "-n", "5", "prompts.jsonl"]).action
                == .judge(input: "prompts.jsonl", model: "gemma.gguf", output: "arbiter.jsonl", limit: 5))
        #expect(try ControlCommandLine.parse(["judge", "-"]).action == .judge(input: "-", model: nil, output: nil, limit: nil))
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["judge"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["judge", "a.jsonl", "b.jsonl"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["judge", "-n", "0", "a.jsonl"]) }
        #expect(ControlCommandLine.usage.contains("judge [-m MODEL]"))
    }

    @Test func readsTheExportAndNamesABadLine() throws {
        let text = #"{"id":"threats-a","system":"S","user":"U"}"# + "\n\n" + #"{"id":"threats-b","system":"S","user":"V"}"# + "\n"
        #expect(try VectorJudge.prompts(jsonl: text).map(\.id) == ["threats-a", "threats-b"])
        #expect(throws: ControlUsageError.self) { try VectorJudge.prompts(jsonl: text + "{\"id\":1}\n") }
    }

    @Test func turnsAReplyIntoAHarnessRowWithLogitConfidence() throws {
        let reply = #"{"outcome":"hold","hold_resolution":"near_line","category":"threats","confidence":0.6,"playbook":"none","staff_alert":false,"emergency_services_first":false,"glam_reply":"","reason":"Ambiguous."}"#
        let row = VectorJudge.row(id: "threats-a", reply: reply,
                                  probabilities: ["pass": 0.1, "nudge": 0.0, "hold": 0.3, "block": 0.0])
        #expect(row.outcome == "hold")
        #expect(row.resolution == "near_line")
        #expect(row.confidence == 0.75)
        #expect(row.confidenceSource == "logits")
        #expect(row.statedConfidence == 0.6)
        #expect(row.outcomeCoverage == 0.4)
        #expect(row.outcomeProbabilities?["pass"] == 0.25)
        #expect(row.staffAlert == false)
        #expect(row.error == nil)

        // The run format the API's report imports (ModerationVectors::Judgment): snake_case, nils left out.
        let json = try #require(JSONSerialization.jsonObject(with: Data(row.jsonLine.utf8)) as? [String: Any])
        #expect(json["id"] as? String == "threats-a")
        #expect(json["emergency_services_first"] as? Bool == false)
        #expect(json["latency_ms"] == nil)
        #expect(!row.jsonLine.contains("\n"))
    }

    @Test func keepsAResolutionOnlyOnAHoldAndFallsBackToTheStatedConfidence() {
        let reply = #"{"outcome":"pass","hold_resolution":"acceptable","category":null,"confidence":0.9,"playbook":"none","staff_alert":false,"emergency_services_first":false,"glam_reply":"","reason":"Fine."}"#
        let row = VectorJudge.row(id: "everyday-a", reply: reply, probabilities: nil)
        #expect(row.resolution == nil)
        #expect(row.category == nil)
        #expect(row.confidence == 0.9)
        #expect(row.confidenceSource == "stated")
    }

    @Test func reportsAnUnusableReplyAsAnErrorRow() {
        #expect(VectorJudge.row(id: "x", reply: "not json", probabilities: nil).error?.hasPrefix("unusable answer") == true)
        #expect(VectorJudge.row(id: "x", reply: #"{"outcome":"maybe"}"#, probabilities: nil).error?.hasPrefix("unknown outcome") == true)
    }

    @Test func resumesFromTheIDsAlreadyAnswered() {
        let text = VectorJudge.Row(id: "a").jsonLine + "\n" + VectorJudge.Row(id: "b", error: "timed out").jsonLine + "\n"
        #expect(VectorJudge.answeredIDs(jsonl: text) == ["a"])
    }

    @Test func holdsTheModelToTheContract() {
        let grammar = VectorJudge.grammar
        #expect(grammar.hasPrefix(#"root ::= "{\"outcome\":\"" outcome"#))
        for value in VectorJudge.outcomes + VectorJudge.playbooks + VectorJudge.resolutions {
            #expect(grammar.contains("\"\(value)\"") || grammar.contains(#"\"\#(value)\""#))
        }
        #expect(VectorJudge.prefix == #"{"outcome":""#)
    }

    @Test func carriesAJudgeRequestAndAnswerOverTheWire() throws {
        let request = ControlRequest(.judge, value: "m.gguf", id: "threats-a", system: "S", user: "U")
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded == request)
        #expect(decoded.command.rawValue == "judge")
        var row = VectorJudge.Row(id: "threats-a")
        row.outcome = "pass"
        let response = ControlResponse(ok: true, judgment: row)
        #expect(try JSONDecoder().decode(ControlResponse.self, from: JSONEncoder().encode(response)).judgment == row)
        // An older app's answer (no judgment field) still decodes.
        let old = #"{"ok":true,"protocolVersion":1}"#
        #expect(try JSONDecoder().decode(ControlResponse.self, from: Data(old.utf8)).judgment == nil)
    }
}
