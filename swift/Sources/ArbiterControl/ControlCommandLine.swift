import Foundation

/// `arbiterctl`'s arguments, read into what to do. Kept here, not in the executable, so the tests cover it.
public struct ControlInvocation: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Send one request and print the answer.
        case request(ControlRequest)
        /// `status --watch`: the status again every `interval` seconds.
        case watch(interval: Double)
        /// `logs --follow`: print new lines as they come.
        case follow(ControlRequest)
        /// `logs --system`: Arbiter's unified log (`log stream`).
        case systemLog
        /// Read a token (from `--token-file`, `--token`, or standard input / a prompt) and sign in with it.
        case signIn(tokenFile: String?, token: String?)
        /// Hand the app an audience's worker token through its URL scheme
        /// (`audiencekit-arbiter://worker-token?audience=<id>&token=<secret>`), which keeps it and starts that audience's
        /// worker and Glam without a sign-in.
        case workerToken(audience: String, tokenFile: String?, token: String?)
        /// Judge each prompt of a moderation:vectors:export file (`-` for standard input) on this Mac, writing the
        /// harness's run rows to `output` (else standard output). `model` picks a model other than the decisions one.
        case judge(input: String, model: String?, output: String?, limit: Int?)
        /// Quit, wait for the app to go, open it again.
        case restart(background: Bool)
        /// Open Arbiter (or bring its window forward).
        case open(background: Bool)
        case help(String?)
        case version
    }

    public var action: Action
    public var json = false
    public var socket: String?

    public init(action: Action, json: Bool = false, socket: String? = nil) {
        self.action = action; self.json = json; self.socket = socket
    }
}

public struct ControlUsageError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public enum ControlCommandLine {
    public static let usage = """
    arbiterctl: control the Arbiter running on this Mac.

    Usage: arbiterctl [--json] [--socket PATH] <command> [options]

    Status
      status [--watch [SECONDS]]     The build, its server, sign-in, the engine and every audience
      audiences                      Each audience's worker and Glam
      account                        Whether Arbiter is signed in, and to which audiences
      ping                           Exit 0 when Arbiter answers

    The engine
      engine start|stop              Every audience's worker and Glam
      worker start|stop [-a NAME]    Workers: one audience (name, prefix or id), else all
      glam start|stop [-a NAME]      Glam the same way
      glam mode [shadow|approve|live]
                                     Show or set this Mac's Glam mode (the console's setting wins where it's set)
      review-only [on|off]           Show or set Review only (on stops every worker and Glam)
      models [rescan]                The models in use and found; rescan looks through the folders again
      embed [-m MODEL] [-d N] TEXT...
                                     Vectors for each TEXT (or each line of standard input with -) from the
                                     embedding model, or MODEL (a slug on Garage's list, or a file); -d N keeps N values
      judge [-m MODEL] [-o OUT] [-n N] PROMPTS.jsonl
                                     Judge the API's moderation test vectors (bin/rails moderation:vectors:export) with
                                     the decisions model, or MODEL; writes one harness row per vector to OUT (else
                                     standard output), skipping ids OUT already has; -n N stops after N; - reads stdin.
                                     Then: bin/rails moderation:vectors:report RUN=... ARBITER=OUT

    Server and account
      server [next|production]       Show the API server, or pick one for the next launch (then: arbiterctl restart)
      sign-in [--token-file PATH]    Sign in with a session token (a JWT, or a sign-in's JSON answer), read from
                                     PATH, standard input, or a hidden prompt; --token TOKEN works but shows in ps
      sign-out --yes                 Sign this Mac out
      worker-token -a AUDIENCE_ID [--token-file PATH]
                                     Give Arbiter an audience's worker token (no sign-in needed): it keeps it and
                                     starts that audience's worker and Glam; read like sign-in's token

    Logs
      logs [-a NAME] [-n N] [-f]     Glam's log and the workers' decisions; -f follows
      logs --system                  Arbiter's unified log (log stream), until ^C

    The app
      open [--background]            Open Arbiter, or bring its window forward
      quit                           Quit, stopping the engine and freeing the models first
      restart [--background]         Quit and open again (a server change takes effect)

    Options
      --json                         Print the app's answer as JSON
      --socket PATH                  Talk to the socket at PATH (also $ARBITER_SOCKET)
    """

    public static func parse(_ arguments: [String]) throws -> ControlInvocation {
        var json = false
        var socket: String?
        var words: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json": json = true
            case "--socket":
                index += 1
                guard index < arguments.count else { throw ControlUsageError("--socket needs a path") }
                socket = arguments[index]
            case "-h", "--help": return ControlInvocation(action: .help(words.first), json: json, socket: socket)
            case "--version": return ControlInvocation(action: .version, json: json, socket: socket)
            default: words.append(argument)
            }
            index += 1
        }
        let action = try parseCommand(words)
        return ControlInvocation(action: action, json: json, socket: socket)
    }

    private static func parseCommand(_ words: [String]) throws -> ControlInvocation.Action {
        guard let command = words.first else { return .help(nil) }
        var rest = Array(words.dropFirst())

        /// Takes `-a NAME` / `--audience NAME` / `--audience=NAME` out of `rest`.
        func takeAudience() throws -> String? {
            try takeValue(["-a", "--audience"])
        }
        func takeValue(_ names: [String]) throws -> String? {
            for (offset, word) in rest.enumerated() {
                if names.contains(word) {
                    guard offset + 1 < rest.count else { throw ControlUsageError("\(word) needs a value") }
                    let value = rest[offset + 1]
                    rest.removeSubrange(offset...(offset + 1))
                    return value
                }
                for name in names where name.hasPrefix("--") && word.hasPrefix(name + "=") {
                    rest.remove(at: offset)
                    return String(word.dropFirst(name.count + 1))
                }
            }
            return nil
        }
        func takeFlag(_ names: String...) -> Bool {
            guard let offset = rest.firstIndex(where: names.contains) else { return false }
            rest.remove(at: offset)
            return true
        }
        func finish() throws {
            guard rest.isEmpty else { throw ControlUsageError("Unexpected: \(rest.joined(separator: " ")) (see arbiterctl --help)") }
        }
        func startStop(_ start: ControlCommand, _ stop: ControlCommand) throws -> ControlCommand {
            guard let verb = rest.first else { throw ControlUsageError("\(command) needs start or stop") }
            rest.removeFirst()
            switch verb {
            case "start", "on", "up": return start
            case "stop", "off", "down": return stop
            default: throw ControlUsageError("\(command) takes start or stop, not \(verb)")
            }
        }

        switch command {
        case "help":
            return .help(rest.first)
        case "version":
            return .version
        case "ping":
            try finish(); return .request(ControlRequest(.ping))
        case "status":
            if takeFlag("--watch", "-w") {
                var interval = 2.0
                if let first = rest.first, let seconds = Double(first), seconds > 0 { interval = seconds; rest.removeFirst() }
                try finish()
                return .watch(interval: interval)
            }
            try finish(); return .request(ControlRequest(.status))
        case "audiences", "account":
            try finish(); return .request(ControlRequest(.status, value: command))
        case "models":
            if rest.isEmpty { return .request(ControlRequest(.status, value: command)) }
            guard rest == ["rescan"] else { throw ControlUsageError("models takes rescan, or nothing") }
            return .request(ControlRequest(.modelsRescan))
        case "embed", "embeddings":
            let model = try takeValue(["-m", "--model"])
            var dimensions: Int?
            if let value = try takeValue(["-d", "--dimensions"]) {
                guard let number = Int(value), number > 0 else { throw ControlUsageError("-d takes a positive number") }
                dimensions = number
            }
            guard !rest.isEmpty else { throw ControlUsageError("embed needs some text (or - to read lines from standard input)") }
            let input = rest
            rest = []
            return .request(ControlRequest(.embed, value: model, input: input, dimensions: dimensions))
        case "judge":
            let model = try takeValue(["-m", "--model"])
            let output = try takeValue(["-o", "--out", "--output"])
            var limit: Int?
            if let value = try takeValue(["-n", "--limit"]) {
                guard let number = Int(value), number > 0 else { throw ControlUsageError("-n takes a positive number") }
                limit = number
            }
            guard rest.count == 1, let input = rest.first else {
                throw ControlUsageError("judge needs one prompts file from bin/rails moderation:vectors:export (or - for standard input)")
            }
            rest = []
            return .judge(input: input, model: model, output: output, limit: limit)
        case "engine":
            let which = try startStop(.engineStart, .engineStop)
            try finish(); return .request(ControlRequest(which))
        case "worker", "workers":
            let which = try startStop(.workerStart, .workerStop)
            let audience = try takeAudience()
            if takeFlag("--all") && audience != nil { throw ControlUsageError("Pick --audience or --all, not both") }
            try finish(); return .request(ControlRequest(which, audience: audience))
        case "glam":
            if rest.first == "mode" {
                rest.removeFirst()
                let value = rest.isEmpty ? nil : rest.removeFirst()
                if let value, !["shadow", "approve", "live"].contains(value) {
                    throw ControlUsageError("Glam's mode is shadow, approve or live, not \(value)")
                }
                try finish(); return .request(ControlRequest(.glamMode, value: value))
            }
            let which = try startStop(.glamStart, .glamStop)
            let audience = try takeAudience()
            if takeFlag("--all") && audience != nil { throw ControlUsageError("Pick --audience or --all, not both") }
            try finish(); return .request(ControlRequest(which, audience: audience))
        case "review-only":
            let value = rest.isEmpty ? nil : rest.removeFirst()
            if let value, !["on", "off"].contains(value) { throw ControlUsageError("review-only takes on or off") }
            try finish(); return .request(ControlRequest(.reviewOnly, value: value))
        case "server":
            let value = rest.isEmpty ? nil : rest.removeFirst()
            if let value, !["next", "production"].contains(value) { throw ControlUsageError("The server is next or production") }
            try finish(); return .request(ControlRequest(.server, value: value))
        case "logs", "log":
            if takeFlag("--system") { try finish(); return .systemLog }
            let audience = try takeAudience()
            var limit: Int? = 50
            if let count = try takeValue(["-n", "--lines"]) {
                guard let number = Int(count), number >= 0 else { throw ControlUsageError("-n takes a number") }
                limit = number
            }
            let follow = takeFlag("-f", "--follow")
            try finish()
            let request = ControlRequest(.logs, audience: audience, limit: limit)
            return follow ? .follow(request) : .request(request)
        case "sign-in", "signin", "login":
            let file = try takeValue(["--token-file", "-f"])
            let token = try takeValue(["--token", "-t"])
            if file != nil && token != nil { throw ControlUsageError("Pick --token-file or --token, not both") }
            try finish(); return .signIn(tokenFile: file, token: token)
        case "worker-token":
            guard let audience = try takeAudience() else { throw ControlUsageError("worker-token needs -a AUDIENCE_ID") }
            let file = try takeValue(["--token-file", "-f"])
            let token = try takeValue(["--token", "-t"])
            if file != nil && token != nil { throw ControlUsageError("Pick --token-file or --token, not both") }
            try finish(); return .workerToken(audience: audience, tokenFile: file, token: token)
        case "sign-out", "signout":
            guard takeFlag("--yes", "-y") else {
                throw ControlUsageError("sign-out signs this Mac out of AudienceKit; run it with --yes to go ahead")
            }
            try finish(); return .request(ControlRequest(.signOut))
        case "open", "show":
            let background = takeFlag("--background", "-g")
            try finish(); return .open(background: background)
        case "quit", "stop":
            try finish(); return .request(ControlRequest(.quit))
        case "restart", "relaunch":
            let background = takeFlag("--background", "-g")
            try finish(); return .restart(background: background)
        default:
            throw ControlUsageError("Unknown command \(command) (see arbiterctl --help)")
        }
    }
}

extension ControlCommandLine {
    /// The app's URL for handing it an audience's worker token.
    public static func workerTokenURL(audience: String, token: String) -> URL? {
        var components = URLComponents()
        components.scheme = "audiencekit-arbiter"
        components.host = "worker-token"
        components.queryItems = [URLQueryItem(name: "audience", value: audience), URLQueryItem(name: "token", value: token)]
        // URLComponents leaves "+" alone in a query, which a reader would take for a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
