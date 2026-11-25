import Foundation
import Testing
@testable import ArbiterModels

/// What `web_search` and `fetch_page` may open, and how they read what Chrome shows.
@Suite struct WebAddressTests {
    @Test(arguments: ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111", "2001:4860:4860::8888", "::ffff:8.8.8.8"])
    func publicAddresses(_ address: String) {
        #expect(WebAddress.isPublic(address))
    }

    @Test(arguments: ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254",
                      "100.64.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "::1", "::", "fe80::1%en0", "fd00::1",
                      "fc12:3456::1", "ff02::1", "::ffff:192.168.1.1", "::ffff:c0a8:101", "2001:db8::1",
                      "64:ff9b::a00:1", "2002:c0a8:101::1", "not an address", "1.2.3", "300.1.1.1"])
    func privateOrInvalidAddresses(_ address: String) {
        #expect(!WebAddress.isPublic(address))
    }

    @Test func opensPublicPages() throws {
        #expect(try WebAddress.check("https://velvet.example.com/events?x=1").host == "velvet.example.com")
        #expect(try WebAddress.check(" http://8.8.8.8/ ").host == "8.8.8.8")
    }

    @Test(arguments: ["file:///etc/passwd", "ftp://example.com/", "javascript:alert(1)", "http://localhost:3000/",
                      "http://printer.local/", "http://router/", "http://10.0.0.1/admin", "http://[::1]:8080/",
                      "http://169.254.169.254/latest/meta-data/", "https://user:pass@example.com/",
                      "http://2130706433/", "http://db.internal/"])
    func refusesLocalPages(_ url: String) {
        #expect(throws: WebAddress.Refused.self) { try WebAddress.check(url) }
    }

    @Test func refusesNamesThatResolveLocally() throws {
        try WebAddress.checkResolved(host: "velvet.example.com", addresses: ["93.184.216.34", "2606:2800:220:1::1"])
        #expect(throws: WebAddress.Refused.self) {
            try WebAddress.checkResolved(host: "rebind.example.com", addresses: ["93.184.216.34", "127.0.0.1"])
        }
        #expect(throws: WebAddress.Refused.self) { try WebAddress.checkResolved(host: "nothing.example", addresses: []) }
    }
}

@Suite struct WebSearchEngineTests {
    @Test func readsDuckDuckGoResults() throws {
        let json = #"{"blocked":false,"results":[{"title":"Velvet SLC","url":"https://duckduckgo.com/l/?uddg=https%3A%2F%2Fvelvet.example%2F","snippet":"Gay bar downtown"},{"title":"Velvet again","url":"https://duckduckgo.com/l/?uddg=https%3A%2F%2Fvelvet.example%2F","snippet":""},{"title":"Ad","url":"https://duckduckgo.com/y.js?ad=1","snippet":""}]}"#
        let results = try #require(WebSearchEngine.duckduckgo.read(json))
        #expect(results == [WebSearchResult(title: "Velvet SLC", url: "https://velvet.example/", snippet: "Gay bar downtown")])
    }

    @Test func readsGoogleResults() throws {
        let json = #"{"blocked":false,"results":[{"title":"Velvet","url":"https://www.google.com/url?q=https://velvet.example/&sa=U","snippet":"Open late"},{"title":"Maps","url":"https://maps.google.com/?q=velvet","snippet":""},{"title":"Two","url":"https://two.example/","snippet":""}]}"#
        let results = try #require(WebSearchEngine.google.read(json, limit: 1))
        #expect(results == [WebSearchResult(title: "Velvet", url: "https://velvet.example/", snippet: "Open late")])
    }

    @Test func aBlockedSearchGoesToTheNextEngine() {
        #expect(WebSearchEngine.google.read(#"{"blocked":true,"results":[]}"#) == nil)
        #expect(WebSearchEngine.google.read("not json") == nil)
        #expect(WebSearchEngine.allCases == [.google, .duckduckgo])
    }

    @Test func searchesTheQuery() {
        #expect(WebSearchEngine.duckduckgo.url(for: "velvet & co").absoluteString
                == "https://html.duckduckgo.com/html/?q=velvet%20%26%20co")
        #expect(WebSearchEngine.google.url(for: "velvet").absoluteString == "https://www.google.com/search?q=velvet&hl=en")
    }
}

@Suite struct WebPageTests {
    @Test func readsAPageInSlices() throws {
        let json = #"{"title":"Velvet","text":"Velvet\nOpen till 2am","structured":[{"@type":"BarOrPub","name":"Velvet"}]}"#
        let first = try #require(WebPageScript.read(json, url: "https://velvet.example/", offset: 0, limit: 6))
        #expect(first.text == "Velvet")
        #expect(first.truncated)
        #expect(first.totalChars == 20)
        #expect(first.structuredData == [.object(["@type": .string("BarOrPub"), "name": .string("Velvet")])])
        let rest = try #require(WebPageScript.read(json, url: "https://velvet.example/", offset: 7, limit: 100))
        #expect(rest.text == "Open till 2am")
        #expect(!rest.truncated)
        let past = try #require(WebPageScript.read(json, url: "https://velvet.example/", offset: 500, limit: 100))
        #expect(past.text.isEmpty)
    }
}

@Suite struct WebPacingTests {
    @Test func spacesSearchesAndCapsTheDay() {
        var pacing = WebPacing(spacing: 4, dailyCap: 2)
        let start = Date(timeIntervalSince1970: 1_793_750_400)   // 2026-11-04 00:00 UTC
        #expect(pacing.reserve(at: start) == 0)
        #expect(pacing.reserve(at: start.addingTimeInterval(1)) == 3)
        #expect(pacing.reserve(at: start.addingTimeInterval(60)) == nil)
        #expect(pacing.reserve(at: start.addingTimeInterval(86_400)) == 0)
    }
}

@Suite struct WebToolsTests {
    struct Browser: WebBrowsing {
        func search(_ query: String, limit: Int) async throws -> WebSearch {
            WebSearch(query: query, engine: .duckduckgo,
                      results: [WebSearchResult(title: "Velvet", url: "https://velvet.example/", snippet: "\(limit)")])
        }
        func fetch(_ url: String, offset: Int) async throws -> WebPage {
            _ = try WebAddress.check(url)
            return WebPage(url: url, title: "Velvet", text: "Open", truncated: false, totalChars: 4, structuredData: [])
        }
    }

    @Test func describesBothTools() {
        #expect(WebTools.definitions.compactMap { $0["name"]?.string } == ["web_search", "fetch_page"])
    }

    @Test func answersAsMCPDoes() async throws {
        let found = await WebTools.call("web_search", arguments: .object(["query": .string("velvet"), "limit": .number(50)]),
                                        browser: Browser())
        #expect(found["isError"] == .bool(false))
        guard case .array(let content)? = found["content"], let text = content.first?["text"]?.string else {
            Issue.record("No content"); return
        }
        let search = try JSONDecoder().decode(WebSearch.self, from: Data(text.utf8))
        #expect(search.engine == .duckduckgo)
        #expect(search.results.first?.snippet == "10")
    }

    @Test func failuresAreToolErrors() async {
        let refused = await WebTools.call("fetch_page", arguments: .object(["url": .string("http://10.0.0.1/")]),
                                          browser: Browser())
        #expect(refused["isError"] == .bool(true))
        #expect(await WebTools.call("web_search", arguments: .object([:]), browser: Browser())["isError"] == .bool(true))
        #expect(await WebTools.call("nope", arguments: .object([:]), browser: Browser())["isError"] == .bool(true))
    }
}
