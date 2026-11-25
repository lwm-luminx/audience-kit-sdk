import Foundation
import Testing
@testable import ArbiterModels

/// The models read what the Electron Arbiter writes (glam/proposals.jsonl), so its logs carry over to the Mac app.
@Suite struct ArbiterModelsTests {
    let electronProposal = #"""
    {"id":"p1","at":"2026-10-26T06:03:12.345Z","mode":"live","room":{"id":"v1","name":"Velvet","kind":"venue"},
     "lines":[{"handle":"h2","role":null,"text":"anyone know when the show starts?","sentAt":"2026-10-26T06:02:00.000Z"},
              {"handle":"h1","role":null,"text":"Glam are you a bot?","sentAt":null}],
     "letters":{"h1":"A","h2":"B"},
     "guard":[{"policy":"instructions_at_bot","model":"shieldgemma","decision":false,"rationale":"",
               "raw":{"pTrue":0.01,"pFalse":0.98,"coverage":0.99,"variantMass":0,"score":0.01},"status":"clear"}],
     "rules":[{"policy":"body_shaming","model":"counted in code","decision":false,"rationale":"","raw":null,
               "status":"unscored","reason":"timeout"}],
     "ruleActions":[{"action":"notify_venue","rule":"unsafe_venue","category":"unsafe_venue","severity":"info",
                     "score":0.8,"reason":"someone needs help"}],
     "injection":false,
     "choice":{"tool":"room_message","method":"logprobs","scores":{"room_message":0.9,"no_action":0.1},
               "conformalSet":["room_message"],"confidence":0.9},
     "call":{"tool":"room_message","arguments":{"text":"I'm Glam, the venue's AI host!","n":2},"rationale":"asked"},
     "errors":[],"gate":{"allowed":true,"needsApproval":false,"blocked":[]},"model":"gemma-4","durationMs":1400,
     "executed":false,"cursor":"c11",
     "execution":{"state":"not_run","steps":[{"field":"say","label":"Say in the room","input":{"cursor":"c11"},
                  "punitive":false}],"note":"Only messages from the live feed are carried out"},
     "label":{"verdict":"wrong_tool","at":"2026-10-26T07:00:00Z"}}
    """#

    @Test func readsAnElectronProposal() throws {
        let proposal = try ArbiterJSON.decoder.decode(GlamProposal.self, from: Data(electronProposal.utf8))
        #expect(proposal.judged?.text == "Glam are you a bot?")
        #expect(proposal.context.map(\.text) == ["anyone know when the show starts?"])
        #expect(proposal.speaker(proposal.lines[0]) == "B")
        #expect(proposal.checks(.securityAndIntegrity)?.first?.raw?.coverage == 0.99)
        #expect(proposal.checks(.moderation)?.first?.status == .unscored)
        #expect(proposal.ruleActions.first?.action == .notifyVenue)
        #expect(proposal.call.arguments["text"]?.string == "I'm Glam, the venue's AI host!")
        #expect(proposal.call.arguments["n"]?.number == 2)
        #expect(proposal.execution?.state == .notRun)
        #expect(proposal.label?.verdict == .wrongTool)
    }

    @Test func roundTrips() throws {
        let proposal = try ArbiterJSON.decoder.decode(GlamProposal.self, from: Data(electronProposal.utf8))
        let again = try ArbiterJSON.decoder.decode(GlamProposal.self, from: ArbiterJSON.encoder.encode(proposal))
        #expect(again == proposal)
    }

    @Test func keepsWhatGlamLookedUpFirst() throws {
        #expect(try ArbiterJSON.decoder.decode(GlamProposal.self, from: Data(electronProposal.utf8)).lookups == nil)
        let looked = electronProposal.replacingOccurrences(
            of: #""cursor":"c11","#,
            with: #""cursor":"c11","lookups":[{"tool":"read_coming_up","info":{"events":[]}},{"tool":"read_venue_info","info":null,"error":"offline"}],"#)
        let proposal = try ArbiterJSON.decoder.decode(GlamProposal.self, from: Data(looked.utf8))
        #expect(proposal.lookups?.map(\.tool) == ["read_coming_up", "read_venue_info"])
        #expect(proposal.lookups?.last?.error == "offline")
        #expect(try ArbiterJSON.decoder.decode(GlamProposal.self, from: ArbiterJSON.encoder.encode(proposal)) == proposal)
    }

    @Test func answerChoiceAndUnsure() {
        let answer = EngineAnswer(scores: ["keep": 0.3, "apply": 0.7], conformalSet: ["apply", "keep"], method: .logprobs)
        #expect(answer.choice == "apply")
        #expect(answer.unsure)
    }

    @Test func aTracedAnswerKeepsItsResultAndAddsHowItWasReached() {
        let answer = EngineAnswer(scores: ["keep": 0.25, "apply": 0.75], conformalSet: ["apply"],
                                  result: .object(["summary": .string("Fits")]), method: .json)
            .traced(durationMs: 1200, engine: "gemma", attempt: 2)
        guard case .object(let result) = answer.result, case .object(let trace) = result["trace"] else {
            Issue.record("no trace"); return
        }
        #expect(result["summary"] == .string("Fits"))
        #expect(trace["method"] == .string("json"))
        #expect(trace["durationMs"] == .number(1200))
        #expect(trace["engine"] == .string("gemma"))
        #expect(trace["attempt"] == .number(2))
        #expect(trace["conformalSet"] == .array([.string("apply")]))
        #expect(trace["scores"] == .object(["keep": .number(0.25), "apply": .number(0.75)]))
        #expect(answer.choice == "apply")
    }

    /// Runs from before configurations were kept belong to the default; a variant's name and settings round-trip.
    @Test func runsKeepTheirConfiguration() throws {
        let old = try ArbiterJSON.decoder.decode(GlamProposal.self, from: Data(electronProposal.utf8))
        #expect(old.configuration == nil && old.settings == nil)

        var engine = EngineSettings(modelPath: "/models/gemma-4.gguf", guardModelPath: "/models/shieldgemma.gguf")
        engine.configuration = "  "
        #expect(engine.configurationName == nil)
        engine.configuration = "guard Q8"
        let variant = GlamProposal(id: "p2", at: old.at, mode: .replay, room: old.room, lines: old.lines,
                                   letters: old.letters, guardChecks: nil, rules: nil, choice: nil, call: old.call,
                                   gate: old.gate, model: "gemma-4", durationMs: 1, cursor: "c1",
                                   configuration: engine.configurationName, settings: RunSettings(engine))
        let json = try ArbiterJSON.encoder.encode(variant)
        let again = try ArbiterJSON.decoder.decode(GlamProposal.self, from: json)
        #expect(again.configuration == "guard Q8")
        #expect(again.settings?.guardModel == "shieldgemma.gguf")
        #expect(String(decoding: json, as: UTF8.self).contains(#""configuration":"guard Q8""#))

        // Settings saved before the field existed still load.
        let saved = try ArbiterJSON.encoder.encode(EngineSettings())
        var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object["configuration"] = nil
        let loaded = try JSONDecoder().decode(EngineSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(loaded.configuration == nil)
    }

    @Test func ruleThresholdsEncodeAsAnObject() throws {
        let settings = EngineSettings(ruleThresholds: ["body_shaming": [.adult: 0.8]])
        let json = String(decoding: try ArbiterJSON.encoder.encode(settings), as: UTF8.self)
        #expect(json.contains(#""ruleThresholds":{"body_shaming":{"adult":0.8}}"#))
    }
}

/// What the admin console sets for an audience (chat.moderation.settings) takes the place of the Mac's own values.
@Suite struct ServerEngineSettingsTests {
    let fromAPI = #"""
    {"configured":true,"updatedAt":"2026-11-01T23:40:00Z","glamMode":"live","roomGuidelines":"Be kind.",
     "ruleThresholds":{"identity_hate":{"adult":0.85}},"guardThresholds":{"rule_override":0.7},"alpha":0.05}
    """#

    @Test func readsOnlyWhatWasSet() throws {
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(fromAPI.utf8))
        #expect(server.configured)
        #expect(server.glamMode == .live)
        #expect(server.venueRating == nil)
        #expect(server.ruleThresholds?["identity_hate"]?[.adult] == 0.85)
        #expect(server.managed == [.glamMode, .roomGuidelines, .ruleThresholds, .guardThresholds, .alpha])
    }

    @Test func takesThePlaceOfTheMacsOwnValues() throws {
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(fromAPI.utf8))
        let mac = EngineSettings(modelPath: "/models/gemma.gguf", guardThresholds: ["format_escape": 0.4],
                                 venueRating: .general, ruleThresholds: ["minors": [.general: 0.3]], glamMode: .shadow,
                                 autoStartGlam: true)
        let applied = mac.applying(server)
        #expect(applied.glamMode == .live)
        #expect(applied.roomGuidelines == "Be kind.")
        #expect(applied.alpha == 0.05)
        #expect(applied.venueRating == .general)
        #expect(applied.guardThresholds == ["rule_override": 0.7])
        #expect(applied.ruleThresholds == ["identity_hate": [.adult: 0.85]])
        #expect(applied.modelPath == "/models/gemma.gguf")
        #expect(applied.autoStartGlam)
        #expect(mac.applying(nil) == mac)
    }

    @Test func namesTheHostAsTheConsoleDoes() throws {
        let server = try JSONDecoder().decode(ServerEngineSettings.self,
                                              from: Data(#"{"configured":true,"hostName":"Hacky"}"#.utf8))
        #expect(server.managed == [.hostName])
        #expect(EngineSettings().host == "Glam")
        #expect(EngineSettings().applying(server).host == "Hacky")
        #expect(EngineSettings(hostName: "  ").host == "Glam")
        // Settings saved before the host had a name still decode.
        let saved = try JSONEncoder().encode(EngineSettings())
        var object = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        object["hostName"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(EngineSettings.self, from: old).host == "Glam")
    }

    @Test func leavesAValueItDoesNotKnowToTheMac() throws {
        let json = #"{"configured":true,"glamMode":"loud","roomGuidelines":"Hi"}"#
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(json.utf8))
        #expect(server.glamMode == nil)
        #expect(server.roomGuidelines == "Hi")
        #expect(EngineSettings(glamMode: .approve).applying(server).glamMode == .approve)
    }

    @Test func readsNothingSetYet() throws {
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(#"{"configured":false,"updatedAt":null}"#.utf8))
        #expect(!server.configured)
        #expect(server.managed.isEmpty)
    }
}


/// The prompts the API serves (MCP prompts/get) fill the Mac's own variables and fall back to the built-in text.
@Suite struct ArbiterPromptSetTests {
    let set = ArbiterPromptSet(prompts: [
        "glam.system": ArbiterPrompt(name: "glam.system", text: "You are Glam on {{model}} at Hot Mess. {{unknown}}",
                                     version: "3+20261104T101500Z", digest: "abcdef0123456789"),
        "decider.system": ArbiterPrompt(name: "decider.system", text: "", version: "1", digest: "e3b0c44298fc1c14"),
    ], updatedAt: "2026-11-04T10:15:00Z")

    @Test func rendersTheMacsVariables() {
        #expect(set.text("glam.system", ["model": "gemma"]) == "You are Glam on gemma at Hot Mess. {{unknown}}")
    }

    @Test func fallsBackWhenMissingOrEmpty() {
        #expect(set.text("guard.system") == nil)
        #expect(set.text("decider.system") == nil)
    }

    @Test func stampsEveryPromptByName() {
        #expect(set.stamps.map(\.name) == ["decider.system", "glam.system"])
        #expect(set.stamps.last == PromptStamp(name: "glam.system", version: "3+20261104T101500Z",
                                               digest: "abcdef0123456789"))
    }

    @Test func roundTripsForTheMacsDefaults() throws {
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(ArbiterPromptSet.self, from: data) == set)
    }

    @Test func serverSettingsSayWhenPromptsChanged() throws {
        let json = #"{"configured":true,"promptsUpdatedAt":"2026-11-04T10:15:00Z"}"#
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(json.utf8))
        #expect(server.promptsUpdatedAt == "2026-11-04T10:15:00Z")
        #expect(server.managed.isEmpty)
    }
}
