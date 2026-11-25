import Foundation
import Testing
@testable import ArbiterModels

/// How research asks for a tool's arguments, reads them back, and turns its steps into what the API keeps.
@Suite struct ResearchTests {
    let venueTool: JSONValue = .object([
        "name": .string("venue"), "description": .string("One venue's listing"),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "venue": .object(["type": .string("string"), "description": .string("Its ID or name")]),
                "days": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("venue")]),
        ]),
    ])

    let proposeTool: JSONValue = .object([
        "name": .string("propose_change"),
        "inputSchema": .object([
            "properties": .object([
                "kind": .object(["type": .string("string"), "enum": .array([.string("correction"), .string("closed")])]),
                "proposed": .object(["type": .string("object")]),
                "evidence": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            ]),
            "required": .array([.string("kind"), .string("proposed")]),
        ]),
    ])

    @Test func readsAToolsArguments() throws {
        let arguments = try #require(ToolArgument.arguments(of: venueTool))
        #expect(arguments == [ToolArgument(name: "venue", description: "Its ID or name", kind: .string, required: true),
                              ToolArgument(name: "days", kind: .integer, required: false)])
    }

    @Test func leavesOutToolsItCannotFill() {
        #expect(ToolArgument.arguments(of: proposeTool) == nil)
        let tools: [JSONValue] = [venueTool, proposeTool, .object(["name": .string("room_info")]),
                                  .object(["name": .string("fetch_page")])]
        #expect(ResearchTools.usable(tools).compactMap { $0["name"]?.string } == ["venue", "fetch_page"])
    }

    @Test func dropsBlankOptionalArguments() throws {
        let arguments = try #require(ToolArgument.arguments(of: venueTool))
        #expect(ToolArgument.values(.object(["venue": .string(" Velvet "), "days": .number(0)]), for: arguments)
                == .object(["venue": .string("Velvet")]))
        #expect(ToolArgument.values(.object(["venue": .string("Velvet"), "days": .number(3)]), for: arguments)
                == .object(["venue": .string("Velvet"), "days": .number(3)]))
    }

    @Test func readsListsChoicesAndFlags() {
        let arguments = [ToolArgument(name: "links", kind: .list, required: true),
                         ToolArgument(name: "kind", kind: .choice(["a", "b"]), required: false),
                         ToolArgument(name: "all", kind: .boolean, required: false),
                         ToolArgument(name: "open", kind: .boolean, required: true)]
        let reply: JSONValue = .object(["links": .string("https://a.example\n\n https://b.example "),
                                        "kind": .string("none"), "all": .string("false"), "open": .string("false")])
        #expect(ToolArgument.values(reply, for: arguments)
                == .object(["links": .array([.string("https://a.example"), .string("https://b.example")]),
                            "open": .bool(false)]))
    }

    @Test func readsAToolsAnswer() {
        let ok: JSONValue = .object(["content": .array([.object(["type": .string("text"), "text": .string("{}")])]),
                                     "isError": .bool(false)])
        #expect(ResearchTools.text(of: ok).text == "{}")
        #expect(!ResearchTools.text(of: ok).isError)
        let failed: JSONValue = .object(["content": .array([]), "isError": .bool(true)])
        #expect(ResearchTools.text(of: failed).text == "The tool failed.")
        #expect(ResearchTools.text(of: failed).isError)
    }

    @Test func evidenceIsOnlyPagesItOpened() throws {
        let page = WebPage(url: "https://velvet.example/", title: "Velvet", text: "Velvet\nOpen till 2am\nCover $10\nMore",
                           truncated: false, totalChars: 30, structuredData: [])
        let pageJSON = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
        let steps = [
            ResearchStep(tool: "web_search", arguments: .object([:]), output: #"{"results":[]}"#, isError: false),
            ResearchStep(tool: "fetch_page", arguments: .object([:]), output: pageJSON, isError: false),
            ResearchStep(tool: "fetch_page", arguments: .object([:]), output: pageJSON, isError: false),
            ResearchStep(tool: "fetch_page", arguments: .object([:]), output: "10.0.0.1 is not a public address.", isError: true),
        ]
        #expect(ResearchFindings.evidence(steps) == [.object(["url": .string("https://velvet.example/"),
                                                               "title": .string("Velvet"),
                                                               "excerpt": .string("Velvet Open till 2am Cover $10")])])
    }

    @Test func proposedFieldsAgainstTheListing() {
        let target: JSONValue = .object(["website": .string("http://old.example"), "phone": .string("555"),
                                         "cover_cents": .number(500)])
        let text = "- website: https://velvet.example\nphone: 555\ncover_cents: 1000\nis_canceled: true\nnot a field line\nbad field!: x\nname:"
        #expect(ResearchFindings.proposedDiff(text, target: target) == .object([
            "website": .object(["from": .string("http://old.example"), "to": .string("https://velvet.example")]),
            "cover_cents": .object(["from": .number(500), "to": .number(1000)]),
            "is_canceled": .object(["from": .null, "to": .bool(true)]),
        ]))
        #expect(ResearchFindings.proposedDiff("", target: nil) == .object([:]))
    }

    @Test func recommendsOnlyWhenSure() {
        let sure = EngineAnswer(scores: ["approve": 0.95, "reject": 0.05], conformalSet: ["approve"], method: .logprobs)
        let unsure = EngineAnswer(scores: ["approve": 0.6, "reject": 0.4], conformalSet: ["approve", "reject"],
                                  method: .logprobs)
        #expect(ResearchFindings.recommendation(sure) == "approve")
        #expect(ResearchFindings.recommendation(unsure) == "unsure")
    }

    @Test func researchesSuggestionsAndArticlesWeighedForNationalNews() throws {
        #expect(ResearchJob.job(for: "submission_research") == .suggestion)
        let national = try #require(ResearchJob.job(for: "article_national_feature"))
        #expect(national.promptKey == "research.national_feature" && national.writeup == .reach)
        #expect(ResearchJob.job(for: "chat_moderation") == nil)
        // An article is read and checked on the web, never turned into a change to a listing.
        let tools: [JSONValue] = ["web_search", "fetch_page", "venue", "suggestions", "propose_change", "place_search"]
            .map { .object(["name": .string($0)]) }
        #expect(ResearchTools.usable(tools, allowed: national.allowed).compactMap { $0["name"]?.string }
                == ["web_search", "fetch_page", "venue"])
        #expect(ResearchTools.usable(tools).compactMap { $0["name"]?.string }
                == ["web_search", "fetch_page", "venue", "suggestions", "place_search"])
    }

    @Test func readsAnArticlesReach() {
        #expect(NationalFeature.reach(" National ") == "national")
        #expect(NationalFeature.reach("regional") == "regional")
        #expect(NationalFeature.reach("everywhere") == nil)
        #expect(NationalFeature.reach(nil) == nil)
    }

    @Test func aMacSetUpBeforeNationalNewsTakesItToo() {
        #expect(EngineSettings().workTypes == ["submission_research", "article_national_feature"])
        #expect(EngineSettings(evaluationTypes: ["submission_research"]).workTypes
                == ["submission_research", "article_national_feature"])
        #expect(EngineSettings(evaluationTypes: ["article_national_feature"]).workTypes == ["article_national_feature"])
        #expect(EngineSettings(evaluationTypes: []).workTypes == [])
    }
}
