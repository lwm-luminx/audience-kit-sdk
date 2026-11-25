import Foundation
import Testing
@testable import ArbiterControl

/// A short socket path of its own (sun_path holds about 104 bytes), removed by the caller.
private func temporarySocket() -> (folder: String, path: String) {
    let folder = "/tmp/akc-" + String(UUID().uuidString.prefix(8))
    return (folder, folder + "/ctl.sock")
}

private func jwt(_ claims: [String: Any]) -> String {
    func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = encode(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
    let payload = encode(try! JSONSerialization.data(withJSONObject: claims))
    return "\(header).\(payload).signature"
}

/// Sends from a GCD thread, not the test's: the client blocks on its read, and the server answers through a Task, which
/// needs a thread of Swift concurrency's pool. Blocking pool threads from tests running side by side starves it on a
/// small CI machine (arbiterctl itself sends from its main thread, outside the pool).
private func send(_ request: ControlRequest, path: String) async throws -> ControlResponse {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(with: Result { try ControlClient.send(request, path: path, timeout: 10) })
        }
    }
}

@Suite("The control socket", .serialized)
struct ControlSocketTests {
    @Test func answersARequestAndReplacesAStaleSocket() async throws {
        let (folder, path) = temporarySocket()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        // A stale socket file from a crashed launch.
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())

        let server = ControlServer(path: path) { request in
            ControlResponse(ok: true, message: "\(request.command.rawValue) \(request.audience ?? "all")")
        }
        try server.start()
        defer { server.stop() }

        let response = try await send(ControlRequest(.workerStart, audience: "Hot Mess"), path: path)
        #expect(response.ok)
        #expect(response.message == "worker.start Hot Mess")
        #expect(response.protocolVersion == ArbiterControl.protocolVersion)
        #expect(ControlClient.answers(path: path))

        // Only this user may use it.
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func aSecondServerOnTheSamePathStaysQuiet() async throws {
        let (folder, path) = temporarySocket()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let first = ControlServer(path: path) { _ in .success("first") }
        try first.start()
        defer { first.stop() }
        let second = ControlServer(path: path) { _ in .success("second") }
        #expect(throws: ControlSocketError.alreadyRunning(path)) { try second.start() }
        #expect(try await send(ControlRequest(.ping), path: path).message == "first")
    }

    @Test func stoppingRemovesTheSocket() throws {
        let (folder, path) = temporarySocket()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let server = ControlServer(path: path) { _ in .success() }
        try server.start()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(throws: ControlSocketError.notRunning(path)) { try ControlClient.send(ControlRequest(.ping), path: path) }
    }

    @Test func aMissingSocketMeansNotRunning() {
        #expect(throws: ControlSocketError.notRunning("/tmp/no-such-arbiter.sock")) {
            try ControlClient.send(ControlRequest(.status), path: "/tmp/no-such-arbiter.sock")
        }
    }

    @Test func aPathTooLongForASocketSaysSo() {
        let path = "/tmp/" + String(repeating: "a", count: 200) + ".sock"
        #expect(throws: ControlSocketError.pathTooLong(path)) { try ControlClient.send(ControlRequest(.ping), path: path) }
    }

    @Test func socketPaths() {
        let home = "/Users/rick"
        #expect(ArbiterControl.serverSocketPath(environment: ["APP_SANDBOX_CONTAINER_ID": "x"],
                                                home: "\(home)/Library/Containers/com.audiencekit.Arbiter/Data")
                == "\(home)/Library/Containers/com.audiencekit.Arbiter/Data/arbiterctl.sock")
        #expect(ArbiterControl.serverSocketPath(environment: [:], home: home)
                == "\(home)/Library/Application Support/Arbiter/arbiterctl.sock")
        #expect(ArbiterControl.clientSocketPaths(environment: [:], home: home).first
                == "\(home)/Library/Containers/com.audiencekit.Arbiter/Data/arbiterctl.sock")
        #expect(ArbiterControl.clientSocketPaths(environment: ["ARBITER_SOCKET": "/tmp/a.sock"], home: home) == ["/tmp/a.sock"])
        // The sandboxed path fits a Unix socket for an ordinary home folder.
        #expect(ArbiterControl.clientSocketPaths(environment: [:], home: "/Users/rickmark")[0].utf8.count < 104)
    }
}

@Suite("arbiterctl's arguments")
struct ControlCommandLineTests {
    func request(_ words: String...) throws -> ControlRequest? {
        if case .request(let request) = try ControlCommandLine.parse(words).action { return request }
        return nil
    }

    @Test func commands() throws {
        #expect(try request("status") == ControlRequest(.status))
        #expect(try request("worker", "start") == ControlRequest(.workerStart))
        #expect(try request("worker", "stop", "-a", "Hot Mess") == ControlRequest(.workerStop, audience: "Hot Mess"))
        #expect(try request("glam", "start", "--audience=hack") == ControlRequest(.glamStart, audience: "hack"))
        #expect(try request("glam", "mode") == ControlRequest(.glamMode))
        #expect(try request("glam", "mode", "live") == ControlRequest(.glamMode, value: "live"))
        #expect(try request("engine", "stop") == ControlRequest(.engineStop))
        #expect(try request("review-only", "on") == ControlRequest(.reviewOnly, value: "on"))
        #expect(try request("server", "next") == ControlRequest(.server, value: "next"))
        #expect(try request("models", "rescan") == ControlRequest(.modelsRescan))
        #expect(try request("audiences") == ControlRequest(.status, value: "audiences"))
        #expect(try request("logs", "-n", "10") == ControlRequest(.logs, limit: 10))
        #expect(try request("sign-out", "--yes") == ControlRequest(.signOut))
        #expect(try request("quit") == ControlRequest(.quit))
    }

    @Test func otherActions() throws {
        #expect(try ControlCommandLine.parse(["status", "--watch", "5"]).action == .watch(interval: 5))
        #expect(try ControlCommandLine.parse(["logs", "-f", "-a", "Hot"]).action
                == .follow(ControlRequest(.logs, audience: "Hot", limit: 50)))
        #expect(try ControlCommandLine.parse(["logs", "--system"]).action == .systemLog)
        #expect(try ControlCommandLine.parse(["embed", "-m", "bge-m3", "-d", "256", "hello", "there"]).action
                == .request(ControlRequest(.embed, value: "bge-m3", input: ["hello", "there"], dimensions: 256)))
        #expect(try ControlCommandLine.parse(["embed", "-"]).action == .request(ControlRequest(.embed, input: ["-"])))
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["embed"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["embed", "-d", "0", "x"]) }
        #expect(try ControlCommandLine.parse(["restart", "-g"]).action == .restart(background: true))
        #expect(try ControlCommandLine.parse(["sign-in", "--token-file", "~/t"]).action == .signIn(tokenFile: "~/t", token: nil))
        #expect(try ControlCommandLine.parse(["worker-token", "-a", "abc"]).action
                == .workerToken(audience: "abc", tokenFile: nil, token: nil))
        let invocation = try ControlCommandLine.parse(["--json", "--socket", "/tmp/x.sock", "status"])
        #expect(invocation.json && invocation.socket == "/tmp/x.sock")
        #expect(try ControlCommandLine.parse([]).action == .help(nil))
    }

    @Test func mistakes() {
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["worker"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["worker", "jump"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["glam", "mode", "loud"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["sign-out"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["status", "extra"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["audiences", "extra"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["worker-token"]) }
        #expect(throws: ControlUsageError.self) { try ControlCommandLine.parse(["frobnicate"]) }
    }

    @Test func workerTokenURLEscapesTheSecret() throws {
        let url = try #require(ControlCommandLine.workerTokenURL(audience: "a1", token: "x+y/z=&w"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(url.scheme == "audiencekit-arbiter" && url.host == "worker-token")
        #expect(items?.first { $0.name == "token" }?.value == "x+y/z=&w")
        #expect(items?.first { $0.name == "audience" }?.value == "a1")
        #expect(!url.absoluteString.contains("+"))
    }
}

@Suite("Sign-in tokens")
struct ControlTokenTests {
    @Test func readsABareJWT() throws {
        let token = jwt(["sub": "u1", "audience_id": "a1", "audience_role": "admin", "role": "user",
                         "aud": "https://api.next.audiencekit.com/v1/audience/a1/staffql"])
        let parsed = try ControlToken.parse("  Bearer \(token)\n")
        #expect(parsed.token == token)
        #expect(parsed.userID == "u1" && parsed.audienceID == "a1" && parsed.role == "admin")
        #expect(parsed.endpoint.host == "api.next.audiencekit.com")
        #expect(parsed.expiresAt == nil)
    }

    @Test func aPlatformSignInIsAdminOnlyForPlatformAdmins() throws {
        let admin = jwt(["sub": "u1", "role": "admin", "aud": "https://api.audiencekit.com/v1/tenants/graphql"])
        #expect(try ControlToken.parse(admin).role == "admin")
        let member = jwt(["sub": "u2", "role": "user", "aud": "https://api.audiencekit.com/v1/tenants/graphql"])
        #expect(try ControlToken.parse(member).role == "member")
        #expect(try ControlToken.parse(member).audienceID == nil)
    }

    @Test func readsASignInAnswer() throws {
        let token = jwt(["sub": "u1", "aud": "https://api.audiencekit.com/v1/staffql"])
        let json = #"{"token":"\#(token)","userId":"u9","audienceId":null,"role":"member","endpoint":"https://api.audiencekit.com/v1/staffql","venueDeviceId":null,"expiresAt":null}"#
        let parsed = try ControlToken.parse(json)
        #expect(parsed.userID == "u9" && parsed.role == "member" && parsed.endpoint.path == "/v1/staffql")
    }

    @Test func refusesWhatIsntASessionToken() {
        #expect(throws: ControlUsageError.self) { try ControlToken.parse("") }
        #expect(throws: ControlUsageError.self) { try ControlToken.parse("not-a-jwt") }
        #expect(throws: ControlUsageError.self) { try ControlToken.parse(jwt(["sub": "u1"])) }
        #expect(throws: ControlUsageError.self) {
            try ControlToken.parse(jwt(["sub": "u1", "aud": "https://api.audiencekit.com/v1/staffql", "exp": 1000]))
        }
    }
}

@Suite("Picking an audience and log lines")
struct ControlMatchTests {
    let candidates: [(id: String, name: String, keys: [String])] = [
        ("hm", "Hot Mess", ["hm", "a-1"]), ("hd", "Hack Different", ["hd", "a-2"]), ("hx", "Hot Takes", ["hx", "a-3"]),
    ]

    @Test func findsByNameIDOrUniquePrefix() {
        #expect(ControlAudienceMatch.find("hot mess", in: candidates) == .found("hm"))
        #expect(ControlAudienceMatch.find("a-2", in: candidates) == .found("hd"))
        #expect(ControlAudienceMatch.find("Hack", in: candidates) == .found("hd"))
        #expect(ControlAudienceMatch.find("Ho", in: candidates) == .ambiguous(["Hot Mess", "Hot Takes"]))
        #expect(ControlAudienceMatch.find("Velvet", in: candidates) == .none)
    }

    @Test func selectsLogLines() {
        let lines = (1...5).map { ControlLogLine(audience: "A", source: .glam, key: "\($0)", at: Double($0), text: "\($0)") }
        #expect(ControlLogLine.select(lines.reversed(), since: nil, limit: 2).map(\.key) == ["4", "5"])
        #expect(ControlLogLine.select(lines, since: 3, limit: nil).map(\.key) == ["3", "4", "5"])
    }

    @Test func formatsAStatus() {
        let status = ControlStatus(
            app: .init(bundleID: "com.audiencekit.Arbiter", version: "1.10", build: "42", debug: false, pid: 7),
            server: .init(current: "next", apiURL: "https://api.next.audiencekit.com", switchable: true, pending: "production"),
            account: .init(signedIn: true, audiences: ["Hot Mess"], opened: ["Hot Mess"], updateRequired: false),
            engine: .init(reviewOnly: false, reviewOnlyForced: false, glamMode: "shadow", modelPath: "/m/gemma.gguf",
                          guardModelPath: nil, modelFolders: [], models: [], downloads: [:], autoStartWorker: true,
                          autoStartGlam: true, error: nil),
            background: nil,
            audiences: [.init(id: "hm", name: "Hot Mess", audienceID: "a-1", hostName: "Glam", current: true,
                              worker: .init(running: true, state: "idle", handled: 3),
                              glam: .init(running: true, state: "watching", backlog: 2))])
        let text = ControlFormat.status(status)
        #expect(text.contains("Arbiter 1.10 (42)"))
        #expect(text.contains("switching to production on restart"))
        #expect(text.contains("gemma.gguf"))
        #expect(text.contains("Hot Mess*"))
        #expect(text.contains("watching (2 waiting)"))
    }
}
