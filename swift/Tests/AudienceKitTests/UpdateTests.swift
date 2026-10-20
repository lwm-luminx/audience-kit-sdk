@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let releaseJSON = #"""
{ "identifier": "social.hotmess.HotMess", "platform": "ios", "environment": "production",
  "app_store_id": "1195758383", "app_store_url": "https://apps.apple.com/app/id1195758383",
  "testflight_url": "https://testflight.apple.com/join/mcPybJVN",
  "testflight": { "latest_build": 420215, "minimum_build": 420180, "latest_version": "2.1", "notes": ["Pair me up to chat"] },
  "app_store": { "latest_build": 420212, "minimum_build": 420004, "latest_version": "2.1", "notes": [] } }
"""#

private func decodeRelease(_ json: String = releaseJSON) throws -> AppRelease {
    try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
}

private func makeSession(_ stub: Stub) -> AudienceSession {
    AudienceSession(configuration: AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com"),
                    session: stub.session)
}

@Suite struct AppReleaseDecoding {
    @Test func decodesTheContract() throws {
        let release = try decodeRelease()

        #expect(release.identifier == "social.hotmess.HotMess")
        #expect(release.platform == "ios")
        #expect(release.environment == "production")
        #expect(release.appStoreID == "1195758383")
        #expect(release.appStoreURL == URL(string: "https://apps.apple.com/app/id1195758383"))
        #expect(release.testFlightURL == URL(string: "https://testflight.apple.com/join/mcPybJVN"))
        #expect(release.testFlight == AppRelease.Channel(latestBuild: 420_215, minimumBuild: 420_180,
                                                         latestVersion: "2.1", notes: ["Pair me up to chat"]))
        #expect(release.appStore == AppRelease.Channel(latestBuild: 420_212, minimumBuild: 420_004,
                                                       latestVersion: "2.1", notes: []))
        #expect(release.channel(for: .testFlight) == release.testFlight)
        #expect(release.channel(for: .appStore) == release.appStore)
        #expect(release.channel(for: .development) == nil)
        #expect(release.channel(for: .unknown) == nil)
    }

    @Test func everyFieldMayBeNull() throws {
        let release = try decodeRelease(#"""
        { "identifier": "social.hotmess.HotMess", "app_store_id": null, "app_store_url": null, "testflight_url": null,
          "testflight": { "latest_build": null, "minimum_build": null, "latest_version": null, "notes": null },
          "app_store": null }
        """#)

        #expect(release.appStoreID == nil)
        #expect(release.appStoreURL == nil)
        #expect(release.testFlightURL == nil)
        #expect(release.testFlight == AppRelease.Channel())
        #expect(release.appStore == nil)
        #expect(release.testFlightLinks.isEmpty)
        #expect(release.appStoreLinks.isEmpty)
    }

    @Test func toleratesNumbersAsStringsAndTheOtherWayRound() throws {
        let release = try decodeRelease(#"""
        { "app_store_id": 1195758383, "testflight": { "latest_build": "420215", "notes": ["  Fixes ", ""] } }
        """#)

        #expect(release.appStoreID == "1195758383")
        #expect(release.testFlight?.latestBuild == 420_215)
        #expect(release.testFlight?.notes == ["Fixes"])
    }

    @Test func roundTripsThroughTheCache() throws {
        let release = try decodeRelease()
        let state = AppReleaseState(release: release, lastChecked: Date(timeIntervalSince1970: 1_800_000_000),
                                    dismissedBuilds: ["testFlight": 420_215])
        let defaults = try #require(UserDefaults(suiteName: "AudienceKitTests.\(UUID().uuidString)"))
        let store = UserDefaultsAppReleaseStore(defaults: defaults, key: "release")

        #expect(store.load() == AppReleaseState())
        store.save(state)
        #expect(store.load() == state)
        #expect(UserDefaultsAppReleaseStore(defaults: defaults, key: "release").load() == state)
    }

    @Test func linksTryTheAppThenTheWeb() throws {
        let release = try decodeRelease()

        #expect(release.testFlightLinks.map(\.absoluteString) == [
            "itms-beta://beta.itunes.apple.com/v1/app/1195758383", "https://testflight.apple.com/join/mcPybJVN",
        ])
        #expect(release.appStoreLinks.map(\.absoluteString) == [
            "itms-apps://apps.apple.com/app/id1195758383", "https://apps.apple.com/app/id1195758383",
        ])

        let idOnly = AppRelease(appStoreID: "id1195758383")
        #expect(idOnly.appStoreLinks.map(\.absoluteString) == [
            "itms-apps://apps.apple.com/app/id1195758383", "https://apps.apple.com/app/id1195758383",
        ])
    }

    @Test func installSourceFromStoreKitEnvironment() {
        #expect(InstallSource(environment: "Sandbox") == .testFlight)
        #expect(InstallSource(environment: "Production") == .appStore)
        #expect(InstallSource(environment: "Xcode") == .development)
        #expect(InstallSource(environment: "LocalTesting") == .unknown)
        #expect(InstallSource.testFlight.isUpdatable && InstallSource.appStore.isUpdatable)
        #expect(!InstallSource.development.isUpdatable && !InstallSource.unknown.isUpdatable)
    }
}

@Suite struct AppReleaseEndpoint {
    @Test func fetchesTheAppsRelease() async throws {
        let stub = Stub { _ in .json(status: 200, body: releaseJSON) }

        let release = try await makeSession(stub).appRelease(app: "social.hotmess.HotMess")

        let request = try #require(stub.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/v1/app_release")
        #expect(request.url.query == "app=social.hotmess.HotMess")
        #expect(request.header("Authorization") == nil)
        #expect(request.header(AudienceKitSDK.apiVersionHeaderName) == AudienceKitSDK.apiVersion)
        #expect(release?.testFlight?.latestBuild == 420_215)
    }

    @Test func anUnknownAppHasNoRelease() async throws {
        let stub = Stub { _ in .json(status: 404, body: #"{"error":"NOT_FOUND","message":"No such app"}"#) }

        #expect(try await makeSession(stub).appRelease(app: "social.hotmess.Unknown") == nil)
    }

    @Test func otherFailuresThrow() async throws {
        let stub = Stub { _ in .json(status: 500, body: "{}") }

        await #expect(throws: AudienceKitError.self) {
            try await makeSession(stub).appRelease(app: "social.hotmess.HotMess")
        }
    }

    @Test func brandingCarriesTheReleaseWhenAskedForTheApp() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"""
            {"audience":{"id":"a-1","name":"Hot Mess","subdomain":"hotmess"},"facebook_app_id":null,
             "theme":{"preset":"hot_mess","light":{},"dark":{}},"app_release":\#(releaseJSON)}
            """#)
        }

        let branding = try await makeSession(stub).branding(app: "social.hotmess.HotMess")

        let request = try #require(stub.requests.first)
        #expect(request.url.query == "host=hotmess.admin.audiencekit.com&app=social.hotmess.HotMess")
        #expect(branding.appRelease?.appStoreID == "1195758383")
    }

    @Test func brandingWithoutAReleaseStillDecodes() throws {
        let branding = try JSONDecoder().decode(Branding.self, from: Data(#"""
        {"audience":{"id":"a-1","name":"Hot Mess","subdomain":"hotmess"},"theme":{"preset":"hot_mess"},"app_release":null}
        """#.utf8))

        #expect(branding.appRelease == nil)
    }
}

@Suite struct UpdateDecisions {
    let release: AppRelease

    init() throws {
        release = try decodeRelease()
    }

    private func prompt(_ source: InstallSource, build: Int?, version: String = "2.0", dismissed: Int? = nil,
                        testFlight: Bool = true, release: AppRelease?? = nil) -> UpdatePrompt?
    {
        UpdateRules.prompt(source: source, release: release ?? self.release, currentBuild: build,
                           currentVersion: version, dismissedBuild: dismissed, canOpenTestFlight: testFlight)
    }

    @Test func comparesBuildNumbersNumerically() {
        #expect(UpdateRules.buildNumber("420212") == 420_212)
        #expect(UpdateRules.buildNumber(" 99 ") == 99)
        #expect(UpdateRules.buildNumber("1.2.3") == nil)
        #expect(UpdateRules.buildNumber(nil) == nil)
        // 9 is older than 10 as numbers, though not as text.
        let release = AppRelease(testFlight: .init(latestBuild: 10))
        #expect(UpdateRules.prompt(source: .testFlight, release: release, currentBuild: 9, currentVersion: "1",
                                   dismissedBuild: nil, canOpenTestFlight: true)?.isBlocking == false)
    }

    @Test func belowTheMinimumBlocks() {
        let result = prompt(.testFlight, build: 420_108)
        #expect(result?.isBlocking == true)
        #expect(result?.offer.channel == .testFlight)
        #expect(result?.offer.currentLabel == "Build 420108")
        #expect(result?.offer.minimumLabel == "Build 420180")
        #expect(result?.offer.latestLabel == "Build 420215")
        // Dismissing never lifts it, nor does a missing TestFlight app.
        #expect(prompt(.testFlight, build: 420_108, dismissed: 420_215, testFlight: false)?.isBlocking == true)
        #expect(prompt(.appStore, build: 420_003)?.isBlocking == true)
    }

    @Test func belowTheLatestIsSoft() {
        guard case let .soft(offer)? = prompt(.testFlight, build: 420_212) else {
            Issue.record("expected a soft prompt")
            return
        }
        #expect(offer.latestBuild == 420_215)
        #expect(offer.notes == ["Pair me up to chat"])
        #expect(offer.updateLinks.first?.scheme == "itms-beta")

        guard case let .soft(appStore)? = prompt(.appStore, build: 420_100, version: "2.0") else {
            Issue.record("expected a soft prompt")
            return
        }
        #expect(appStore.latestLabel == "Version 2.1")
        #expect(appStore.currentLabel == "Version 2.0")
        #expect(appStore.updateLinks.first?.scheme == "itms-apps")
    }

    @Test func eachChannelHasItsOwnBuilds() {
        // 420213 is behind TestFlight's 420215 but ahead of the App Store's 420212.
        #expect(prompt(.testFlight, build: 420_213) != nil)
        #expect(prompt(.appStore, build: 420_213) == nil)
    }

    @Test func currentOrNewerIsNothing() {
        #expect(prompt(.testFlight, build: 420_215) == nil)
        #expect(prompt(.testFlight, build: 420_300) == nil)
    }

    @Test func aDismissedBuildIsSkippedUntilANewerOne() {
        #expect(prompt(.testFlight, build: 420_212, dismissed: 420_215) == nil)
        #expect(prompt(.testFlight, build: 420_212, dismissed: 420_214) != nil)
    }

    @Test func withoutTestFlightTheSoftPromptSaysSo() {
        guard case .noTestFlight? = prompt(.testFlight, build: 420_212, testFlight: false) else {
            Issue.record("expected the TestFlight-missing prompt")
            return
        }
        #expect(prompt(.testFlight, build: 420_215, testFlight: false) == nil)
        // App Store installs don't need TestFlight.
        guard case .soft? = prompt(.appStore, build: 420_100, testFlight: false) else {
            Issue.record("expected a soft prompt")
            return
        }
    }

    @Test func developmentAndUnknownInstallsSeeNothing() {
        #expect(prompt(.development, build: 1) == nil)
        #expect(prompt(.unknown, build: 1) == nil)
    }

    @Test func noConfigIsNothing() {
        #expect(prompt(.testFlight, build: 1, release: .some(nil)) == nil)
        #expect(prompt(.appStore, build: 1, release: .some(AppRelease(testFlight: .init(latestBuild: 5)))) == nil)
        #expect(prompt(.testFlight, build: 1, release: .some(AppRelease(testFlight: .init()))) == nil)
        #expect(prompt(.testFlight, build: nil) == nil)
    }

    @Test func throttlesToOncePerInterval() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateRules.shouldCheck(lastChecked: nil, now: now))
        #expect(!UpdateRules.shouldCheck(lastChecked: now.addingTimeInterval(-3600), now: now))
        #expect(UpdateRules.shouldCheck(lastChecked: now.addingTimeInterval(-86_400), now: now))
        #expect(UpdateRules.shouldCheck(lastChecked: now.addingTimeInterval(3600), now: now))
        #expect(!UpdateRules.shouldCheck(lastChecked: now.addingTimeInterval(-60), now: now, interval: 120))
    }

    @Test func aboutRows() {
        #expect(UpdateText.installedFrom(.testFlight) == "TestFlight beta")
        #expect(UpdateText.installedFrom(.appStore) == "App Store")
        #expect(UpdateText.installedFrom(.development) == nil)
        #expect(UpdateText.updatesRowTitle(.testFlight) == "Beta updates")
        #expect(UpdateText.updatesRowTitle(.appStore) == "Updates")

        let available = UpdateRules.status(source: .testFlight, release: release, currentBuild: 420_212,
                                           currentVersion: "2.1")
        #expect(UpdateText.status(available) == "Build 420215 ready")
        let appStore = UpdateRules.status(source: .appStore, release: release, currentBuild: 420_100,
                                          currentVersion: "2.0")
        #expect(UpdateText.status(appStore) == "Version 2.1 ready")
        let current = UpdateRules.status(source: .appStore, release: release, currentBuild: 420_212,
                                         currentVersion: "2.1")
        #expect(UpdateText.status(current) == "Up to date")
        #expect(UpdateRules.status(source: .development, release: release, currentBuild: 1, currentVersion: "1")
            == .unknown)
    }
}

/// Counts fetches and answers with whatever `release` holds, or fails while `offline`.
private final class FakeAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var _release: AppRelease?
    private var _offline = false
    private var _fetches = 0
    private var _now = Date(timeIntervalSince1970: 1_800_000_000)

    init(_ release: AppRelease?) { _release = release }

    var release: AppRelease? {
        get { lock.withLock { _release } }
        set { lock.withLock { _release = newValue } }
    }

    var offline: Bool {
        get { lock.withLock { _offline } }
        set { lock.withLock { _offline = newValue } }
    }

    var fetches: Int { lock.withLock { _fetches } }

    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    func fetch() throws -> AppRelease? {
        try lock.withLock {
            _fetches += 1
            if _offline { throw URLError(.notConnectedToInternet) }
            return _release
        }
    }
}

@MainActor
@Suite struct UpdateChecker {
    private func makeUpdates(_ api: FakeAPI, source: InstallSource = .testFlight, build: Int? = 420_212,
                             store: InMemoryAppReleaseStore = InMemoryAppReleaseStore(),
                             testFlightInstalled: Bool = true, opened: OpenedLinks? = nil) -> AudienceUpdates
    {
        AudienceUpdates(app: "social.hotmess.HotMess", appName: "Hot Mess", currentBuild: build,
                        currentVersion: "2.1", store: store,
                        fetch: { try api.fetch() }, installSource: { source },
                        testFlightInstalled: { _ in testFlightInstalled },
                        openURL: { url in opened?.open(url) ?? false },
                        now: { api.now })
    }

    @Test func showsASoftPromptOnceAndRemembersNotNow() async throws {
        let api = FakeAPI(try decodeRelease())
        let store = InMemoryAppReleaseStore()
        let updates = makeUpdates(api, store: store)

        await updates.checkOnForeground()
        guard case .soft? = updates.prompt else {
            Issue.record("expected a soft prompt")
            return
        }
        #expect(updates.installSource == .testFlight)
        #expect(updates.lastChecked == api.now)

        updates.dismiss()
        #expect(updates.prompt == nil)
        #expect(store.load().dismissedBuilds == ["testFlight": 420_215])
        #expect(updates.pendingUpdate == nil)
        #expect(updates.availableUpdate?.latestBuild == 420_215)

        // A day later the same build stays dismissed; a newer one shows.
        api.now = api.now.addingTimeInterval(86_400)
        await updates.checkOnForeground()
        #expect(updates.prompt == nil)

        var newer = try decodeRelease()
        newer.testFlight?.latestBuild = 420_220
        api.release = newer
        await updates.checkNow()
        #expect(updates.prompt?.offer.latestBuild == 420_220)
    }

    @Test func fetchesAtMostOncePerIntervalUnlessAsked() async throws {
        let api = FakeAPI(try decodeRelease())
        let updates = makeUpdates(api)

        await updates.checkOnForeground()
        api.now = api.now.addingTimeInterval(3600)
        await updates.checkOnForeground()
        #expect(api.fetches == 1)

        await updates.checkNow()
        #expect(api.fetches == 2)

        api.now = api.now.addingTimeInterval(86_400)
        await updates.checkOnForeground()
        #expect(api.fetches == 3)
    }

    @Test func aSoftPromptNeedsAFreshCheck() async throws {
        let api = FakeAPI(try decodeRelease())
        let store = InMemoryAppReleaseStore()
        await makeUpdates(api, store: store).checkOnForeground()

        // Relaunched within the day: the stored config is current, so no fetch and no soft prompt again.
        let relaunched = makeUpdates(api, store: store)
        await relaunched.checkOnForeground()
        #expect(api.fetches == 1)
        #expect(relaunched.prompt == nil)
        #expect(relaunched.pendingUpdate?.latestBuild == 420_215)
    }

    @Test func blocksOfflineFromTheStoredConfig() async throws {
        let api = FakeAPI(try decodeRelease())
        let store = InMemoryAppReleaseStore()
        await makeUpdates(api, build: 420_100, store: store).checkOnForeground()

        api.offline = true
        let relaunched = makeUpdates(api, build: 420_100, store: store)
        await relaunched.checkOnForeground()
        #expect(relaunched.prompt?.isBlocking == true)

        // "Not now" doesn't apply to the blocking screen.
        relaunched.dismiss()
        #expect(relaunched.prompt?.isBlocking == true)
    }

    @Test func nothingStoredAndOfflineShowsNothing() async throws {
        let api = FakeAPI(try decodeRelease())
        api.offline = true
        let updates = makeUpdates(api, build: 1)

        await updates.checkOnForeground()
        #expect(updates.prompt == nil)
        #expect(updates.lastChecked == nil)
        #expect(updates.status == .unknown)
    }

    @Test func anUnknownAppClearsTheConfig() async throws {
        let api = FakeAPI(try decodeRelease())
        let store = InMemoryAppReleaseStore()
        let updates = makeUpdates(api, build: 420_100, store: store)
        await updates.checkOnForeground()
        #expect(updates.prompt?.isBlocking == true)

        api.release = nil
        await updates.checkNow()
        #expect(updates.prompt == nil)
        #expect(store.load().release == nil)
    }

    @Test func developmentInstallsNeverFetch() async throws {
        let api = FakeAPI(try decodeRelease())
        for source in [InstallSource.development, .unknown] {
            let updates = makeUpdates(api, source: source, build: 1)
            await updates.checkNow()
            #expect(updates.prompt == nil)
            #expect(updates.status == .unknown)
        }
        #expect(api.fetches == 0)
    }

    @Test func missingTestFlightAppSendsToTheAppStore() async throws {
        let api = FakeAPI(try decodeRelease())
        let opened = OpenedLinks(accepting: ["itms-apps"])
        let updates = makeUpdates(api, testFlightInstalled: false, opened: opened)

        await updates.checkOnForeground()
        guard case .noTestFlight? = updates.prompt else {
            Issue.record("expected the TestFlight-missing prompt")
            return
        }
        #expect(await updates.openAppStore())
        #expect(opened.links == ["itms-apps://apps.apple.com/app/id1195758383"])
    }

    @Test func updateFallsBackToTheWebLink() async throws {
        let api = FakeAPI(try decodeRelease())
        let opened = OpenedLinks(accepting: ["https"])
        let updates = makeUpdates(api, opened: opened)
        await updates.checkOnForeground()

        #expect(await updates.openUpdate())
        #expect(opened.links == [
            "itms-beta://beta.itunes.apple.com/v1/app/1195758383", "https://testflight.apple.com/join/mcPybJVN",
        ])
    }

    @Test func publishesPromptsToTheCustomUIHook() async throws {
        let api = FakeAPI(try decodeRelease())
        let updates = makeUpdates(api)
        let seen = SeenPrompts()
        updates.onPrompt = { seen.prompts.append($0) }
        #expect(await firstPrompt(updates) == .some(nil))

        await updates.checkOnForeground()
        #expect(seen.prompts.count == 1)
        #expect(seen.prompts.first??.offer.latestBuild == 420_215)
        // Each subscription starts with the prompt as it stands.
        #expect(await firstPrompt(updates)??.offer.latestBuild == 420_215)

        updates.dismiss()
        #expect(seen.prompts.count == 2)
        #expect(seen.prompts.last == .some(nil))
    }

    private func firstPrompt(_ updates: AudienceUpdates) async -> UpdatePrompt?? {
        for await prompt in updates.prompts {
            return .some(prompt)
        }
        return .none
    }
}

@MainActor
private final class SeenPrompts {
    var prompts: [UpdatePrompt?] = []
}

/// Records the links an `AudienceUpdates` tried, opening those with an accepted scheme.
@MainActor
private final class OpenedLinks {
    private let accepting: Set<String>
    private(set) var links: [String] = []

    init(accepting: Set<String>) { self.accepting = accepting }

    func open(_ url: URL) -> Bool {
        links.append(url.absoluteString)
        return accepting.contains(url.scheme ?? "")
    }
}
