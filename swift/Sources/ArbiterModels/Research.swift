import Foundation

// Researching a suggestion (evaluation type `submission_research`) on the Mac: Arbiter's model works the API's MCP
// tools (the listings, the suggestions, Google Places) and its own Chrome tools (web_search, fetch_page) one call at a
// time, then the decisions model scores the options with what it found. What's here doesn't need a model: which tools
// research may use, how a tool's arguments are asked for and read back, and how the steps become the result the
// API keeps (Contributions::Research::RESULT_KEYS: recommendation, summary, evidence, proposed_diff, model).

/// The tools research may call, described and answered as MCP's `tools/list` and `tools/call` do. StaffKit's
/// `MCPResearchToolbox` puts the API's MCP tools and the Mac's web tools together.
public protocol ResearchToolbox: Sendable {
    /// Every tool on offer, as MCP describes one (`name`, `description`, `inputSchema`).
    func tools() async throws -> [JSONValue]
    /// Runs one tool; a failure is an answer with `isError`, never a throw.
    func call(_ name: String, arguments: JSONValue) async -> JSONValue
}

public enum ResearchTools {
    /// The evaluation type research answers.
    public static let evaluationType = "submission_research"

    /// The tools research may call, of those the API and the Mac offer: reading the listings and suggestions, Google
    /// Places and the web. Not room_info (it answers a chat message), not the diagnostics tools, and not
    /// propose_change yet (its `proposed` is an object the model can't fill one field at a time).
    public static let allowed: Set<String> = ["venue", "event", "find_venues", "find_events", "suggestions", "suggestion",
                                              "place_search", "place_details", "web_search", "fetch_page"]

    /// The tool descriptions research may use, in the order given.
    public static func usable(_ tools: [JSONValue], allowed: Set<String> = allowed) -> [JSONValue] {
        tools.filter { tool in
            guard let name = tool["name"]?.string, allowed.contains(name) else { return false }
            return ToolArgument.arguments(of: tool) != nil
        }
    }

    /// The text of a `tools/call` answer, and whether it's an error.
    public static func text(of answer: JSONValue) -> (text: String, isError: Bool) {
        var parts: [String] = []
        if case .array(let content)? = answer["content"] {
            for item in content { if let text = item["text"]?.string { parts.append(text) } }
        }
        let text = parts.joined(separator: "\n")
        if case .bool(true)? = answer["isError"] { return (text.isEmpty ? "The tool failed." : text, true) }
        return (text, false)
    }
}

/// A kind of work Arbiter researches before the decisions model scores it: which evaluation type, the API's prompt
/// for it, the tools it may call, and what its write-up holds. Anything else is decided as it is.
public struct ResearchJob: Sendable, Hashable {
    /// What the write-up holds besides the summary.
    public enum Writeup: Sendable, Hashable {
        /// The listing fields that should change, one `field: value` per line (a suggestion).
        case proposedChanges
        /// How far the story reaches: national, regional or local (an article weighed for national news).
        case reach
    }

    public let evaluationType: String
    /// The API's system prompt for it (`config/arbiter/prompts`), served per audience.
    public let promptKey: String
    public let allowed: Set<String>
    /// How the work's input is introduced to the model.
    public let subject: String
    /// When to stop looking.
    public let finishWhen: String
    public let writeup: Writeup

    public init(evaluationType: String, promptKey: String, allowed: Set<String>, subject: String, finishWhen: String,
                writeup: Writeup) {
        self.evaluationType = evaluationType; self.promptKey = promptKey; self.allowed = allowed
        self.subject = subject; self.finishWhen = finishWhen; self.writeup = writeup
    }

    /// A suggestion about a listing (`submission_research`).
    public static let suggestion = ResearchJob(
        evaluationType: ResearchTools.evaluationType, promptKey: "research.system", allowed: ResearchTools.allowed,
        subject: "The suggestion to check", finishWhen: "what you've found settles the suggestion",
        writeup: .proposedChanges)

    /// A Soapbox publisher's article, weighed for the audience's national news (`article_national_feature`, the
    /// API's NationalFeatures). Arbiter recommends; a person decides every one in the decision queue.
    public static let nationalFeature = ResearchJob(
        evaluationType: NationalFeature.evaluationType, promptKey: NationalFeature.promptKey,
        allowed: NationalFeature.allowed, subject: "The article to weigh for national news",
        finishWhen: "you can tell whether it matters beyond its locale", writeup: .reach)

    public static let all: [ResearchJob] = [.suggestion, .nationalFeature]

    /// The job for a type of work, or nil when it's decided without research.
    public static func job(for evaluationType: String) -> ResearchJob? {
        all.first { $0.evaluationType == evaluationType }
    }
}

/// Weighing a Soapbox article for the audience's national news (api doc/SOAPBOX.md "National news").
public enum NationalFeature {
    /// The evaluation type the API queues each day for the newest articles from trusted publications.
    public static let evaluationType = "article_national_feature"
    public static let promptKey = "research.national_feature"
    /// Reading the article's own page and the web, and the listings it's about. Never proposing changes: nothing here
    /// edits a listing.
    public static let allowed: Set<String> = ["web_search", "fetch_page", "venue", "event", "find_venues", "find_events"]
    /// How far a story reaches, as the write-up says it.
    public static let reaches = ["national", "regional", "local"]

    /// The reach the model wrote, or nil when it isn't one of `reaches`.
    public static func reach(_ text: String?) -> String? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return reaches.contains(value) ? value : nil
    }
}

/// One argument of a tool, as its JSON Schema describes it, in a form a grammar can ask for.
public struct ToolArgument: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case string
        case integer
        case number
        case boolean
        /// A string from a fixed list (`enum`).
        case choice([String])
        /// A list of strings, asked for as one string with one item per line.
        case list
    }

    public let name: String
    public let description: String?
    public let kind: Kind
    public let required: Bool

    public init(name: String, description: String? = nil, kind: Kind, required: Bool) {
        self.name = name; self.description = description; self.kind = kind; self.required = required
    }

    /// A tool's arguments, required ones first; nil when a required one is something the model can't be asked for one
    /// field at a time (an object, a list of objects), so the tool isn't offered. Optional ones like that are left out.
    public static func arguments(of tool: JSONValue) -> [ToolArgument]? {
        let schema = tool["inputSchema"]
        let required: Set<String> = {
            guard case .array(let names)? = schema?["required"] else { return [] }
            return Set(names.compactMap(\.string))
        }()
        guard case .object(let properties)? = schema?["properties"] else { return [] }
        var arguments: [ToolArgument] = []
        for (name, property) in properties.sorted(by: { $0.key < $1.key }) {
            let isRequired = required.contains(name)
            guard let kind = kind(of: property) else {
                if isRequired { return nil }
                continue
            }
            arguments.append(ToolArgument(name: name, description: property["description"]?.string, kind: kind,
                                          required: isRequired))
        }
        return arguments.filter(\.required) + arguments.filter { !$0.required }
    }

    private static func kind(of property: JSONValue) -> Kind? {
        if case .array(let values)? = property["enum"] {
            let choices = values.compactMap(\.string)
            return choices.isEmpty ? nil : .choice(choices)
        }
        switch property["type"]?.string {
        case "string": return .string
        case "integer": return .integer
        case "number": return .number
        case "boolean": return .boolean
        case "array": return property["items"]?["type"]?.string == "string" ? .list : nil
        default: return nil
        }
    }

    /// What the model wrote, read back as the tool takes it. The grammar asks for every argument, so an optional one
    /// left blank (an empty string, "none", 0 for a count, an empty list) is dropped rather than sent.
    public static func values(_ reply: JSONValue, for arguments: [ToolArgument]) -> JSONValue {
        var values: [String: JSONValue] = [:]
        for argument in arguments {
            guard let raw = reply[argument.name] else { continue }
            let value: JSONValue?
            switch argument.kind {
            case .string, .choice:
                let text = raw.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                value = text.isEmpty || (!argument.required && ["none", "null", "-"].contains(text.lowercased()))
                    ? nil : .string(text)
            case .integer, .number:
                let number: Double? = raw.number ?? raw.string.flatMap { Double($0) }
                if let number, argument.required || number != 0 { value = .number(number) } else { value = nil }
            case .boolean:
                switch raw {
                case .bool(let flag): value = .bool(flag)
                case .string(let text): value = ["true", "yes"].contains(text.lowercased()) ? .bool(true)
                    : ["false", "no"].contains(text.lowercased()) ? .bool(false) : nil
                default: value = nil
                }
                if !argument.required, value == .bool(false) { continue }
            case .list:
                let items = (raw.string ?? "").split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                value = items.isEmpty ? nil : .array(items.map(JSONValue.string))
            }
            if let value { values[argument.name] = value }
        }
        return .object(values)
    }
}

/// One tool call research made, and what came back (cut short for the model to read).
public struct ResearchStep: Codable, Sendable, Hashable {
    public let tool: String
    public let arguments: JSONValue
    public let output: String
    public let isError: Bool

    public init(tool: String, arguments: JSONValue, output: String, isError: Bool) {
        self.tool = tool; self.arguments = arguments; self.output = output; self.isError = isError
    }
}

/// What research found, as the API keeps it on the evaluation's result.
public enum ResearchFindings {
    /// The pages research actually opened (fetch_page answers that worked), as evidence: url, title and the start of
    /// the page's text. Only pages it read count, never a search result it didn't open.
    public static func evidence(_ steps: [ResearchStep], limit: Int = 10) -> [JSONValue] {
        var seen = Set<String>()
        var evidence: [JSONValue] = []
        for step in steps where step.tool == "fetch_page" && !step.isError {
            guard let page = try? JSONDecoder().decode(WebPage.self, from: Data(step.output.utf8)),
                  seen.insert(page.url).inserted else { continue }
            let excerpt = page.text.split(whereSeparator: \.isNewline).prefix(3).joined(separator: " ")
            evidence.append(.object(["url": .string(page.url), "title": .string(page.title),
                                     "excerpt": .string(String(excerpt.prefix(240)))]))
        }
        return Array(evidence.prefix(limit))
    }

    /// The fields research found should change, from the model's lines of `field: value`, each with what the listing
    /// says now (`from`, from the evaluation's `target`) and what it should be (`to`). "true"/"false" and whole numbers
    /// read as such; a field with the value the listing already has is left out.
    public static func proposedDiff(_ text: String, target: JSONValue?) -> JSONValue {
        var diff: [String: JSONValue] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[..<colon].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*• \"'`"))
            let raw = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            guard !field.isEmpty, !raw.isEmpty,
                  field.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            let to: JSONValue = raw == "true" ? .bool(true) : raw == "false" ? .bool(false)
                : (Int(raw).map { .number(Double($0)) } ?? .string(raw))
            let from = target?[field] ?? .null
            if from == to || from.string == raw { continue }
            diff[field] = .object(["from": from, "to": to])
        }
        return .object(diff)
    }

    /// The recommendation the API keeps: the option the scores chose, or unsure when the set holds more than one.
    public static func recommendation(_ answer: EngineAnswer) -> String {
        answer.unsure ? "unsure" : (answer.choice ?? "unsure")
    }
}
