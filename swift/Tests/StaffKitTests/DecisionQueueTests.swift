import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func queueClient(_ stub: Stub) -> DecisionQueueClient {
    DecisionQueueClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func lastRequest(_ stub: Stub) throws -> (query: String, variables: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    return (body["query"] as? String ?? "", body["variables"] as? [String: Any] ?? [:])
}

private let options = #"[{"key":"approve","label":"Approve","description":"Apply it","score":0.48,"inConformalSet":true},{"key":"reject","label":"Reject","description":null,"score":0.07,"inConformalSet":false},{"key":"needs_venue","label":"Ask the venue","description":null,"score":0.45,"inConformalSet":true}]"#
private let submission = #"{"id":"s1","kind":"CORRECTION","status":"PENDING","proposed":{"phone_number":"+1 206 555 0100","website":"https://eagle.example"},"current":{"phone_number":"+1 206 555 0199","website":null},"venue":{"id":"v1","name":"The Eagle"},"event":null}"#
private func decision(id: String = "d1", unsure: Bool = true, needsPersonAt: String? = "2026-10-26T18:00:00Z",
                      decidedAt: String? = nil, decidedOption: String? = nil, decidedBy: String? = nil) -> String {
    let at = needsPersonAt.map { "\"\($0)\"" } ?? "null"
    let decided = decidedAt.map { "\"\($0)\"" } ?? "null"
    let option = decidedOption.map { "\"\($0)\"" } ?? "null"
    let by = decidedBy.map { #"{"id":"u1","name":"\#($0)","avatarUrl":null}"# } ?? "null"
    return #"{"id":"\#(id)","evaluationType":"submission_research","decisionKind":"CHOICE","question":"Should this suggestion change the listing?","state":"completed","choice":"approve","confidence":0.48,"unsure":\#(unsure),"error":null,"input":{"venue":"The Eagle"},"result":{"summary":"Two numbers online; Google has the new one.","evidence":["https://maps.example/eagle",{"url":"https://eagle.example/contact"},"not a link"],"model":"gemma-4-31b"},"createdAt":"2026-10-26T17:00:00Z","completedAt":"2026-10-26T17:59:00Z","needsPersonAt":\#(at),"decidedAt":\#(decided),"decidedOption":\#(option),"decidedBy":\#(by),"options":\#(options),"submission":\#(submission)}"#
}
private func decode(_ json: String) throws -> StaffDecision {
    try JSONDecoder().decode(StaffDecision.self, from: Data(json.utf8))
}

@Test func aDecisionDecodesWithTheWorkersOddsAndTheSuggestion() throws {
    let open = try decode(decision())
    #expect(open.needsPerson && !open.isDecided && open.decider == .nobody)
    #expect(open.choiceLabel == "Approve" && open.confidence == 0.48)
    #expect(open.optionsByScore.map(\.key) == ["approve", "needs_venue", "reject"])
    #expect(open.options.filter(\.inConformalSet).count == 2)
    #expect(open.reason == "Two numbers online; Google has the new one." && open.model == "gemma-4-31b")
    #expect(open.evidence.map(\.absoluteString) == ["https://maps.example/eagle", "https://eagle.example/contact"])
    #expect(open.title == "Correction · The Eagle")
    let changes = try #require(open.submission).changes
    #expect(changes.map(\.title) == ["Phone number", "Website"])
    #expect(changes[0].now == "+1 206 555 0199" && changes[0].proposed == "+1 206 555 0100" && changes[0].changes)
    #expect(changes[1].now == nil && changes[1].proposed == "https://eagle.example")
}

@Test func aDecisionNobodySignedWasTheAIs() throws {
    let auto = try decode(decision(unsure: false, needsPersonAt: nil, decidedAt: "2026-10-26T18:01:00Z", decidedOption: "approve"))
    #expect(auto.decider == .ai && auto.isDecided && !auto.needsPerson && auto.personAgreedWithAI == nil)
    let overruled = try decode(decision(decidedAt: "2026-10-26T18:02:00Z", decidedOption: "needs_venue", decidedBy: "Rick Mark"))
    #expect(overruled.decider == .person(Profile(id: "u1", name: "Rick Mark")))
    #expect(overruled.personAgreedWithAI == false && overruled.decidedLabel == "Ask the venue")
}

@Test func theQueueAsksForOpenOrDecidedPagesWithTheSuggestion() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"decisions":{"totalCount":1,"nodes":[\#(decision())],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#) }
    let page = try await queueClient(stub).decisions(open: false)
    #expect(page.totalCount == 1 && page.nodes.first?.id == "d1")
    let (query, variables) = try lastRequest(stub)
    #expect(query.contains("decisions(open: $open, first: $first, after: $after)"))
    #expect(query.contains("decidedBy { id name avatarUrl }") && query.contains("submission { id kind status proposed current"))
    #expect(variables["open"] as? Bool == false && variables["first"] as? Int == DecisionQueueClient.pageSize)
    #expect(try #require(stub.requests.last).path.hasSuffix("staffql"))
}

@Test func decidingSendsTheOptionAndATrimmedNote() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"decideEvaluation":{"decision":\#(decision(decidedAt: "2026-10-26T18:03:00Z", decidedOption: "reject", decidedBy: "Rick Mark"))}}}"#) }
    let decided = try await queueClient(stub).decide("d1", option: "reject", note: "  Old number  ")
    #expect(decided.decidedOption == "reject")
    let input = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(input["id"] as? String == "d1" && input["option"] as? String == "reject" && input["note"] as? String == "Old number")
    _ = try await queueClient(stub).decide("d1", option: "approve", note: "   ")
    let bare = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(bare["note"] == nil)
}

@Test func theFeedTurnsChangesIntoQueueEvents() throws {
    let added = Data(#"{"data":{"decisionQueue":{"change":"ADDED","decision":\#(decision())}}}"#.utf8)
    guard case .added(let first)? = DecisionQueueClient.queueEvent(from: added) else { Issue.record("not added"); return }
    #expect(first.id == "d1")
    let waiting = Data(#"{"data":{"decisionQueue":{"change":"WAITING","decision":\#(decision(needsPersonAt: nil))}}}"#.utf8)
    if case .waiting? = DecisionQueueClient.queueEvent(from: waiting) {} else { Issue.record("not waiting") }
    let refused = Data(#"{"data":null,"errors":[{"message":"Not allowed"}]}"#.utf8)
    #expect(DecisionQueueClient.queueEvent(from: refused) == .rejected)
    let later = Data(#"{"data":{"decisionQueue":{"change":"REOPENED","decision":\#(decision())}}}"#.utf8)
    #expect(DecisionQueueClient.queueEvent(from: later) == nil)
    #expect(DecisionQueueClient.queueEvent(from: .disconnected(reason: nil, reconnects: true)) == .offline(nil))
    #expect(DecisionQueueClient.queueEvent(from: .disconnected(reason: nil, reconnects: false)) == .offline("Signed out"))
}

@Test func theQueueStateFollowsChanges() throws {
    let sure = try decode(decision(id: "sure", unsure: false, needsPersonAt: "2026-10-26T17:00:00Z"))
    let late = try decode(decision(id: "late", unsure: true, needsPersonAt: "2026-10-26T18:30:00Z"))
    let early = try decode(decision(id: "early", unsure: true, needsPersonAt: "2026-10-26T18:00:00Z"))
    var state = DecisionQueueState(open: [late])
    state = state.applying(.added(sure)).applying(.added(early))
    // Unsure first, then the longest waiting.
    #expect(state.open.map(\.id) == ["early", "late", "sure"])
    let byAI = try decode(decision(id: "sure", unsure: false, needsPersonAt: nil, decidedAt: "2026-10-26T18:40:00Z", decidedOption: "approve"))
    let byRick = try decode(decision(id: "early", decidedAt: "2026-10-26T18:41:00Z", decidedOption: "reject", decidedBy: "Rick Mark"))
    state = state.applying(.decided(byAI)).applying(.decided(byRick))
    #expect(state.open.map(\.id) == ["late"])
    #expect(state.decided.map(\.id) == ["early", "sure"])
    #expect(state.decidedByAI.map(\.id) == ["sure"] && state.decidedByPeople.map(\.id) == ["early"])
    state = state.applying(.waiting(late))
    #expect(state.open.isEmpty && state.decision("early")?.decidedOption == "reject")
}

@Test func jsonValuesReadAsText() {
    #expect(GraphQLValue.double(3).displayText == "3" && GraphQLValue.double(2.5).displayText == "2.5")
    #expect(GraphQLValue.array([.string("Fri"), .string("Sat")]).displayText == "Fri, Sat")
    #expect(GraphQLValue.object(["b": .bool(true), "a": .null]).displayText == "a: —; b: Yes")
}

@Test func theDecisionQueueDocumentsUseTheStaffSchemasNames() {
    #expect(DecisionQueueClient.decideMutation.contains("decideEvaluation(input: $input)"))
    #expect(DecisionQueueClient.queueSubscription.contains("decisionQueue { change decision {"))
}

@Test func aNationalNewsDecisionShowsTheArticleItWeighs() throws {
    let json = #"{"id":"d9","evaluationType":"article_national_feature","decisionKind":"CHOICE","question":"Should this article be featured nationally?","state":"completed","choice":"feature","confidence":0.97,"unsure":false,"error":null,"input":{"article_id":"a1","title":"Utah court strikes down drag ban","summary":"A ruling with reach.","byline":"QSaltLake","canonical_url":"https://qsaltlake.example/ruling","publication":{"name":"QSaltLake","locale":"Salt Lake City"}},"result":{"summary":"National outlets haven't covered it yet.","reach":"national","model":"gemma-4-31b"},"createdAt":"2026-11-15T13:00:00Z","completedAt":"2026-11-15T13:05:00Z","needsPersonAt":"2026-11-15T13:05:00Z","decidedAt":null,"decidedOption":null,"decidedBy":null,"options":[{"key":"feature","label":"Feature nationally","description":null,"score":0.97,"inConformalSet":true},{"key":"keep_local","label":"Keep it local","description":null,"score":0.03,"inConformalSet":false}],"submission":null}"#
    let national = try decode(json)
    // Sure, but still waiting for a person: the API never features an article on the AI's answer.
    #expect(national.needsPerson && !national.unsure)
    let article = try #require(national.article)
    #expect(article.title == "Utah court strikes down drag ban" && article.publication == "QSaltLake")
    #expect(article.locale == "Salt Lake City" && article.url?.host() == "qsaltlake.example")
    #expect(national.title == "National news · Utah court strikes down drag ban")
    #expect(national.kindTitle == "National news" && national.reach == "national")
    #expect(try decode(decision()).article == nil)
}
