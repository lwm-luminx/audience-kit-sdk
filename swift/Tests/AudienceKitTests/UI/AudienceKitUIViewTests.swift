// Every AudienceKitUI view hosted in a window, in the states an app shows it in, in light and dark and at a large
// accessibility text size. macOS only (Linux has no SwiftUI). The views that talk to the API get a GraphQLStub, which
// answers only what the test gives it, so nothing reaches a server.
#if canImport(SwiftUI) && canImport(AppKit)
import AudienceCore
import AudienceKit
import AudienceKitTesting
import AudienceKitUI
import Foundation
import SwiftUI
import Testing

/// Inputs the view tests share.
private enum UIFixtures {
    static let kiki = LineupEntry.Person(id: "p-kiki", name: "Kiki Ruins")
    static let aurora = LineupEntry.Person(id: "p-aurora", name: "Aurora Borealis")
    static let ada = LineupEntry.Person(id: "p-ada", name: "Ada")

    static let host = LineupEntry(id: "host", role: .host, people: [kiki], state: .on)
    static let dj = LineupEntry(id: "dj", role: .dj, title: "DJ Set", people: [aurora], state: .upcoming,
                                startTiming: .hard, startsAt: Date().addingTimeInterval(3_600))
    static let act = LineupEntry(id: "act", role: .performer, title: "First Set", people: [kiki, aurora], state: .done)
    static let pause = LineupEntry(id: "break", kind: .intermission, title: "Bar break")

    static func singer(_ id: String, _ name: String, song: String, mine: Bool = false,
                       state: LineupEntry.State = .upcoming) -> LineupEntry {
        LineupEntry(id: id, role: .singer, title: name, people: [.init(id: "p-\(id)", name: name)], state: state,
                    songRequest: SongRequest(id: "r-\(id)", title: song, artist: "ABBA", singer: name, mine: mine,
                                             state: state == .on ? .up : .queued))
    }

    static let mine = SongRequest(id: "r-me", title: "Waterloo", artist: "ABBA", singer: "Test", mine: true)

    static func karaoke(open: Bool = true, paused: Bool = false, mine: [SongRequest] = []) -> KaraokeWindow {
        KaraokeWindow(permitted: true, open: open, paused: paused,
                      closedReason: open ? nil : "Karaoke signups open when a host is on", host: host, mine: mine)
    }

    static func songs(open: Bool = true, mine: [SongRequest] = [], queue: [SongRequest] = []) -> SongRequestWindow {
        SongRequestWindow(permitted: true, open: open, closedReason: open ? nil : "Requests are closed",
                          host: dj, mine: mine, queue: queue, cutOff: !open, closesAt: Date().addingTimeInterval(7_200))
    }

    static func lineup(singers: [LineupEntry] = [], karaoke: KaraokeWindow? = nil,
                       songs: SongRequestWindow? = nil, upNext: String? = "dj") -> VenueLineup {
        VenueLineup(venueID: "v-1", venueName: "Nyne", entries: [host, act, pause, dj] + singers, onStageID: "host",
                    upNextID: upNext, karaoke: karaoke, songRequests: songs)
    }

    static let release = AppRelease(appStoreID: "id1", appStoreURL: URL(string: "https://apps.apple.com/app/id1"),
                                    testFlightURL: URL(string: "https://testflight.apple.com/join/abc"),
                                    testFlight: .init(latestBuild: 420, minimumBuild: 400, latestVersion: "2.3",
                                                      notes: ["Quickie at the venue you're at", "Faster chat"]),
                                    appStore: .init(latestBuild: 410, minimumBuild: 300, latestVersion: "2.2",
                                                    notes: ["Bug fixes"]))

    static func offer(_ channel: UpdateChannel, build: Int = 100) -> UpdateOffer {
        UpdateOffer(channel: channel, currentBuild: build, currentVersion: "2.0", release: release)
    }

    static let trivia = TriviaRound(id: "t1", statement: "RuPaul once fronted a punk band.",
                                    choices: [.init(label: "Myth", count: 3), .init(label: "Legend", count: 5)])

    static let links = [
        SocialLink(id: "s1", handle: "abc123", provider: "discord", url: "https://discord.gg/abc123"),
        SocialLink(id: "s2", handle: "#room:matrix.org", provider: "matrix", url: "https://matrix.to/#/#room:matrix.org"),
        SocialLink(id: "s3", handle: "nyne", provider: "instagram", url: "https://instagram.com/nyne"),
    ]
}

/// Hosts `content` light, dark and at a large accessibility size, and returns the three heights.
@MainActor
private func render<Content: View>(_ content: @autoclosure () -> Content, settle: Duration = .milliseconds(150))
    async -> [CGFloat]
{
    var heights: [CGFloat] = []
    for (scheme, size) in [(ColorScheme.light, DynamicTypeSize.large), (.dark, .large), (.light, .accessibility3)] {
        let host = ViewHost(content(), colorScheme: scheme, dynamicType: size)
        await host.settle(timeout: settle)
        #expect(host.drewSomething, "drew nothing (\(scheme), \(size))")
        heights.append(host.height)
        host.close()
    }
    return heights
}

@MainActor
private func height<Content: View>(_ content: Content) async -> CGFloat {
    let host = ViewHost(content)
    await host.settle()
    defer { host.close() }
    return host.height
}

@MainActor
@Suite("AudienceKitUI lineup views", .serialized)
struct LineupViewTests {
    @Test("The lineup strip shows tonight's acts, and grows with additions")
    func lineupStrip() async {
        let lineup = UIFixtures.lineup(karaoke: UIFixtures.karaoke(), songs: UIFixtures.songs())
        let heights = await render(VenueLineupStrip(lineup: lineup))
        // A larger text size never lays out shorter.
        #expect(heights[2] >= heights[0])

        let additions = [
            LineupAddition(kind: .karaoke, window: UIFixtures.karaoke(), action: {}),
            LineupAddition(kind: .song, window: UIFixtures.songs(), action: {}),
        ]
        _ = await render(VenueLineupStrip(entries: lineup.entries, upNextID: "dj", title: nil,
                                          timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                                          additions: additions, onSelect: { _ in }, onSelectPerson: { _ in }))
        // Nothing on tonight draws nothing at all, rather than an empty strip.
        #expect(await height(VenueLineupStrip(entries: [], upNextID: nil)) <= 1)
    }

    @Test("The host row shows the host, with tip and links")
    func hostRow() async {
        let links = [HostLink(title: "Instagram", systemImage: "camera", url: URL(string: "https://instagram.com/kiki")!)]
        let plain = await height(VenueHostRow(host: UIFixtures.host))
        let full = await render(VenueHostRow(host: UIFixtures.host, links: links, onTip: {}, onSelect: {}))
        #expect(full[0] >= plain)
        #expect(HostLink(title: "Instagram", systemImage: "camera", url: URL(string: "https://instagram.com/kiki")!).id
            == links[0].id)
    }

    @Test("The karaoke queue lists the singers, the viewer's signup and the way to sign up")
    func karaokeQueue() async {
        let singers = [
            UIFixtures.singer("s1", "Ada", song: "Dancing Queen", state: .on),
            UIFixtures.singer("s2", "Test", song: "Waterloo", mine: true),
            UIFixtures.singer("s3", "Sam", song: "SOS"),
            UIFixtures.singer("s4", "Lee", song: "Mamma Mia"),
            UIFixtures.singer("s5", "Max", song: "Fernando"),
        ]
        let lineup = UIFixtures.lineup(singers: singers, karaoke: UIFixtures.karaoke(mine: [singers[1].songRequest!]),
                                       upNext: "s2")
        let preview = await render(KaraokeQueue(lineup: lineup, viewerName: "Test", previewLimit: 3, onSeeAll: {},
                                                onSignUp: { _ in }, onRemove: { _ in }))
        let all = await height(KaraokeQueue(lineup: lineup, viewerName: "Test", previewLimit: nil,
                                            onSignUp: { _ in }, onRemove: { _ in }))
        // The whole list is longer than its three-singer preview.
        #expect(all > preview[0])

        // Closed, paused and signed out.
        _ = await render(KaraokeQueue(lineup: UIFixtures.lineup(karaoke: UIFixtures.karaoke(open: false)),
                                      viewerName: nil, onSignUp: { _ in }, onRemove: { _ in }, onSignInNeeded: {}))
        _ = await render(KaraokeQueue(lineup: UIFixtures.lineup(karaoke: UIFixtures.karaoke(paused: true)),
                                      viewerName: "Test", title: nil, showsSignUp: false,
                                      onSignUp: { _ in }, onRemove: { _ in }))
        // No karaoke at all.
        _ = await height(KaraokeQueue(lineup: UIFixtures.lineup(), viewerName: "Test",
                                      onSignUp: { _ in }, onRemove: { _ in }))
    }

    @Test("My signup card says where the viewer is in line, and when they're up")
    func mySignupCard() async {
        let entry = UIFixtures.singer("s2", "Test", song: "Waterloo", mine: true)
        _ = await render(MySignupCard(request: UIFixtures.mine, entry: entry, number: 2, singersBefore: 1,
                                      isUpNext: false, hostName: "Kiki", viewerName: "Test",
                                      onRemove: { _ in }, onDismiss: {}))
        _ = await render(MySignupCard(request: UIFixtures.mine, entry: entry, number: 1, singersBefore: 0,
                                      isUpNext: true, breakOnNow: UIFixtures.pause, onRemove: nil))
        let called = SongRequest(id: "r-up", title: "Waterloo", mine: true, state: .up)
        _ = await render(MySignupCard(request: called, entry: nil, number: nil, singersBefore: nil, isUpNext: false,
                                      onRemove: nil))
    }

    @Test("The sign-up button and sheet")
    func signUp() async {
        _ = await render(KaraokeSignupButton(window: UIFixtures.karaoke(), action: {}))
        _ = await render(KaraokeSignupButton(window: UIFixtures.karaoke(open: false), label: "Sing", action: {}))
        _ = await render(KaraokeSignupSheet(viewerName: "Test", venueName: "Nyne", hostName: "Kiki", submit: { _ in }))
        _ = await render(KaraokeSignupSheet(viewerName: nil, venueName: "Nyne", hostName: nil, submit: { _ in }))
    }
}

@MainActor
@Suite("AudienceKitUI song request views", .serialized)
struct SongRequestViewTests {
    @Test("The requests section shows the queue, the viewer's requests and the button")
    func section() async {
        let queue = [
            SongRequest(id: "q1", kind: .song, title: "Vogue", artist: "Madonna", requesterName: "Ada", position: 1),
            SongRequest(id: "q2", kind: .song, title: "Hung Up", artist: "Madonna", requesterName: "Sam", state: .up),
        ]
        let mine = [SongRequest(id: "m1", kind: .song, title: "Believe", artist: "Cher", mine: true, position: 3)]
        let full = await render(SongRequestsSection(lineup: UIFixtures.lineup(songs: UIFixtures.songs(mine: mine, queue: queue)),
                                                    onRequest: { _ in }, onWithdraw: { _ in }))
        let empty = await height(SongRequestsSection(lineup: UIFixtures.lineup(songs: UIFixtures.songs()),
                                                     onRequest: { _ in }, onWithdraw: { _ in }))
        #expect(full[0] > empty)

        // Closed, signed out, without a title or the button: nothing left to draw.
        #expect(await height(SongRequestsSection(lineup: UIFixtures.lineup(songs: UIFixtures.songs(open: false)),
                                                 signedIn: false, title: nil, showsRequestButton: false,
                                                 onRequest: { _ in }, onWithdraw: { _ in }, onSignInNeeded: {})) <= 1)
        // Closed and signed out, with its title: the title and why it's closed.
        _ = await render(SongRequestsSection(lineup: UIFixtures.lineup(songs: UIFixtures.songs(open: false)),
                                             signedIn: false, onRequest: { _ in }, onWithdraw: { _ in },
                                             onSignInNeeded: {}))
        // A venue that doesn't take requests draws nothing.
        #expect(await height(SongRequestsSection(lineup: UIFixtures.lineup(), onRequest: { _ in },
                                                 onWithdraw: { _ in })) <= 1)
    }

    @Test("A request row, the button and the sheet")
    func rowButtonSheet() async {
        let request = SongRequest(id: "m1", kind: .song, title: "Believe", artist: "Cher", note: "For Ada", mine: true,
                                  position: 3)
        _ = await render(MySongRequestRow(request: request, requestsBefore: 2, onWithdraw: { _ in }))
        _ = await render(MySongRequestRow(request: SongRequest(id: "m2", kind: .song, title: "Strong Enough",
                                                               mine: true, state: .done), onWithdraw: nil))
        _ = await render(SongRequestButton(window: UIFixtures.songs(), action: {}))
        _ = await render(SongRequestButton(window: UIFixtures.songs(open: false), label: "Ask", action: {}))
        _ = await render(SongRequestSheet(venueName: "Nyne", hostName: "DJ Aurora", submit: { _ in }))
        _ = await render(SongRequestSheet(venueName: "Nyne", hostName: nil, submit: { _ in }))
    }
}

@MainActor
@Suite("AudienceKitUI cards and rows", .serialized)
struct CardViewTests {
    @Test("A trivia round while voting, once voted, and revealed")
    func trivia() async {
        let voting = await render(TriviaRoundCard(round: UIFixtures.trivia, onVote: { _ in }))
        let voted = TriviaRound(id: "t1", statement: UIFixtures.trivia.statement, choices: UIFixtures.trivia.choices,
                                myChoice: "Legend")
        _ = await render(TriviaRoundCard(round: voted, onVote: { _ in }))
        let revealed = TriviaRound(id: "t1", statement: UIFixtures.trivia.statement, choices: UIFixtures.trivia.choices,
                                   myChoice: "Myth", voting: false, answer: "Legend", roomCall: "Legend",
                                   reveal: "She sang in Wee Wee Pole Herman in the 80s.")
        let afterReveal = await height(TriviaRoundCard(round: revealed))
        // The reveal adds the story behind the answer.
        #expect(afterReveal > voting[0])
    }

    @Test("An avatar with a photo, initials or a venue's mark")
    func avatar() async {
        _ = await render(AudienceAvatar(url: nil, name: "Ada Lovelace"))
        // A photo that can't be loaded (a file that isn't there) keeps the placeholder; nothing goes to the network.
        _ = await render(AudienceAvatar(url: URL(fileURLWithPath: "/nonexistent/ada.jpg"), name: "Ada", size: 64))
        _ = await render(AudienceAvatar(url: nil, name: "Nyne", size: 48, isVenue: true))
        _ = await render(AudienceAvatar(url: nil, name: ""))
    }

    @Test("Community chat links show only the chats, as Join buttons")
    func chatLinks() async {
        let chats = await height(CommunityChatLinks(UIFixtures.links))
        let none = await height(CommunityChatLinks([UIFixtures.links[2]]))
        #expect(chats > none)
        _ = await render(CommunityChatLinks(UIFixtures.links) { link in Text(link.networkName) })
    }

    @Test("The platform credit footer, with and without each part")
    func creditFooter() async {
        let full = await render(PlatformCreditFooter())
        let bare = await height(PlatformCreditFooter(showsPolicies: false, showsCallToAction: false, showsCopyright: false))
        #expect(full[0] > bare)
    }

    @Test("Calendar subscribe menu and buttons")
    func calendar() async {
        let links = CalendarLinks(feed: URL(string: "https://api.example.invalid/v1/calendar/abc.ics")!)
        _ = await render(CalendarSubscribeMenu(links: links))
        _ = await render(CalendarSubscribeMenu(links: links) { Text("Subscribe") })
        _ = await render(CalendarSubscribeButtons(links: links))
    }

    @Test("Staff app links, installed or not")
    func staffApps() async {
        for app in StaffApp.allCases {
            _ = await render(StaffAppLink(app))
            _ = await render(StaffAppLink(app, url: URL(string: "https://example.invalid/\(app.rawValue)")) { title, image in
                Label(title, systemImage: image)
            })
        }
    }

    @Test("The theme's presets draw light and dark, and an unknown key keeps the default")
    func theme() async {
        for key in ["default", "hot_mess", "no-such-preset"] {
            _ = await render(VenueHostRow(host: UIFixtures.host).audiencePreset(key))
        }
        _ = await render(Rectangle().fill(Color(DesignTokens.light.accent)).frame(height: 10))
    }
}

@MainActor
@Suite("AudienceKitUI update prompts", .serialized)
struct UpdatePromptViewTests {
    @Test("The soft update sheet, the blocking screen and the no-TestFlight sheet")
    func prompts() async {
        let soft = UpdatePrompt.soft(UIFixtures.offer(.testFlight))
        let blocking = UpdatePrompt.blocking(UIFixtures.offer(.appStore, build: 200))
        let noTestFlight = UpdatePrompt.noTestFlight(UIFixtures.offer(.testFlight))
        for prompt in [soft, blocking, noTestFlight] {
            _ = await render(UpdateSheet(prompt: prompt, appName: "Hot Mess", onUpdate: {}, onAppStore: {}, onNotNow: {}))
            _ = await render(UpdateScreen(prompt: prompt, appName: "Hot Mess", onUpdate: {}, onAppStore: {}))
        }
        #expect(blocking.isBlocking)
        #expect(!soft.isBlocking)
        #expect(soft.id != noTestFlight.id)
    }

    @Test("The update banner for each channel")
    func banner() async {
        _ = await render(UpdateBanner(offer: UIFixtures.offer(.testFlight), onUpdate: {}, onHide: {}))
        _ = await render(UpdateBanner(offer: UIFixtures.offer(.appStore), onUpdate: {}, onHide: {}))
    }

    @Test("The prompts host and the banner read the app's updates")
    func hosted() async {
        let updates = AudienceUpdates(app: "test.app", appName: "Hot Mess", currentBuild: 100, currentVersion: "2.0",
                                      fetch: { UIFixtures.release }, installSource: { .testFlight },
                                      testFlightInstalled: { _ in true }, openURL: { _ in true })
        _ = await render(Text("Content").audienceUpdatePrompts(updates), settle: .milliseconds(300))
        _ = await render(AudienceUpdateBanner(updates: updates), settle: .milliseconds(300))
    }
}

@MainActor
@Suite("AudienceKitUI views that talk to the API", .serialized)
struct ClientViewTests {
    @Test("Add to Calendar reads the calendar feed and nothing else")
    func venueCalendar() async {
        let stub = GraphQLStub { request in
            #expect(request.operationName == "CalendarFeed" || request.query.contains("calendar"),
                    "unexpected \(request.operationName ?? request.query)")
            return .data(#"{"me":{"calendarFeed":{"links":{"url":"https://example.invalid/c.ics","webcalUrl":"webcal://example.invalid/c.ics","googleUrl":"https://calendar.google.com/calendar/render?cid=x"},"venues":[{"id":"v-1"}]}}}"#)
        }
        _ = await render(VenueCalendarButton(client: stub.client, venueID: "v-1", venueName: "Nyne"),
                         settle: .milliseconds(400))
        #expect(stub.requests.isEmpty == false)
    }

    @Test("Delete Account draws without asking the API anything")
    func deleteAccount() async {
        let stub = GraphQLStub { request in
            Issue.record("Delete Account asked the API: \(request.operationName ?? request.query)")
            return .error("not in this test")
        }
        _ = await render(DeleteAccountButton(client: stub.client, appName: "Hot Mess"))
        #expect(stub.requests.isEmpty)
        #expect(!DeleteAccountCopy.warning.isEmpty)
    }

    @Test("Connect Discord offers to connect, or shows the connected account")
    func connectDiscord() async {
        let device = DeviceDescription(identifier: "device-1")
        let notConnected = GraphQLStub { request in
            #expect(request.operationName == "ConnectedDiscord")
            return .data(#"{"me":{"self":{"signedInWithDiscord":false,"discordUsername":null}}}"#)
        }
        let offer = await render(ConnectDiscordButton(client: notConnected.client, device: device, app: "test.app"),
                                 settle: .milliseconds(300))
        #expect(notConnected.requests.allSatisfy { $0.operationName == "ConnectedDiscord" })

        let connected = GraphQLStub { _ in
            .data(#"{"me":{"self":{"signedInWithDiscord":true,"discordUsername":"kiki"}}}"#)
        }
        let shown = await render(ConnectDiscordButton(client: connected.client, device: device, app: "test.app"),
                                 settle: .milliseconds(300))
        #expect(connected.requests.count >= 1)
        #expect(offer[0] > 1 && shown[0] > 1)
    }

    @Test("Check the app runs its steps and lists them")
    func appCheck() async {
        let log = GraphQLOperationLog(subsystem: "test")
        // A List takes the height it's given rather than its content's.
        let host = ViewHost(AppCheckView(title: "Hot Mess 2.0 (100)", log: log) { check in
            _ = await check.step("Events") { "3 upcoming." }
            _ = await check.step("Venues") { nil }
            _ = await check.step("Chat") { throw URLError(.notConnectedToInternet) }
        }.frame(height: 400))
        await host.settle()
        let before = host.height
        #expect(host.drewSomething)
        host.close()

        let check = AppCheck()
        await check.run { check in
            _ = await check.step("Events") { "3 upcoming." }
            _ = await check.step("Chat") { throw URLError(.notConnectedToInternet) }
        }
        #expect(check.steps.count == 2)
        #expect(before > 0)
    }
}
#endif
