import Foundation

/// `arbiterctl judge`: Arbiter as Tier 2 for the API's moderation test vectors (audience_kit_api,
/// doc/moderation_vectors/README.md). `bin/rails moderation:vectors:export` writes one `{id, system, user}` prompt per
/// line; arbiterctl sends each to the app, the decisions model answers in the harness's JSON contract (held to it by a
/// grammar), and each answer comes back as one row in the harness's run format, ready for
/// `bin/rails moderation:vectors:report RUN=… ARBITER=arbiter.jsonl`.
///
/// `confidence` is read from the raw logits where the outcome is written (the four outcomes' probabilities, renormalised
/// over the four), not the number the model writes; that one is kept as `stated_confidence`.
public enum VectorJudge {
    public static let outcomes = ["pass", "nudge", "hold", "block"]
    public static let resolutions = ["acceptable", "unacceptable", "near_line"]
    /// The API's JudgePrompt::PLAYBOOKS.
    public static let playbooks = ["none", "unresponsive_person", "hard_signs", "overdose_suspected", "drink_spiking",
                                   "medical_other", "self_harm_plan", "self_harm_acted", "threat_of_violence",
                                   "harassment_report", "feel_unsafe_checkin", "fire_or_evacuation"]

    /// What the reply starts with: the outcome is the first thing written, so its probabilities are read right after.
    public static let prefix = #"{"outcome":""#

    /// The harness's answer contract (JudgePrompt::CONTRACT) as GBNF, keys in its order, outcome first.
    public static let grammar: String = {
        func quoted(_ values: [String]) -> String { values.map { #""\"\#($0)\"""# }.joined(separator: " | ") }
        func bare(_ values: [String]) -> String { values.map { #""\#($0)""# }.joined(separator: " | ") }
        return [
            #"root ::= "{\"outcome\":\"" outcome "\",\"hold_resolution\":" resolution ",\"category\":" category ",\"confidence\":" number ",\"playbook\":\"" playbook "\",\"staff_alert\":" bool ",\"emergency_services_first\":" bool ",\"glam_reply\":\"" char{0,280} "\",\"reason\":\"" char{0,300} "\"}""#,
            "outcome ::= " + bare(outcomes),
            #"resolution ::= "null" | "# + quoted(resolutions),
            #"category ::= "null" | "\"" [a-z_]{1,40} "\"""#,
            #"number ::= "0" ( "." [0-9]{1,3} )? | "1" ( ".0" )?"#,
            "playbook ::= " + bare(playbooks),
            #"bool ::= "true" | "false""#,
            #"char ::= [^"\\\x00-\x1f] | "\\" ["\\/bnrt]"#,
        ].joined(separator: "\n")
    }()

    /// One line of `moderation:vectors:export`.
    public struct Prompt: Codable, Sendable, Hashable {
        public var id: String
        public var system: String
        public var user: String
        public init(id: String, system: String, user: String) { self.id = id; self.system = system; self.user = user }
    }

    /// Reads the export's JSONL, skipping blank lines. Throws naming the first bad line.
    public static func prompts(jsonl text: String) throws -> [Prompt] {
        var prompts: [Prompt] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            do {
                prompts.append(try JSONDecoder().decode(Prompt.self, from: Data(trimmed.utf8)))
            } catch {
                throw ControlUsageError("Line \(index + 1) isn't an {id, system, user} prompt (bin/rails moderation:vectors:export)")
            }
        }
        return prompts
    }

    /// The ids already answered in a run file, so a run that stopped picks up where it left off.
    public static func answeredIDs(jsonl text: String) -> Set<String> {
        var ids = Set<String>()
        for line in text.split(separator: "\n") {
            guard let row = try? JSONDecoder().decode(Row.self, from: Data(line.utf8)), row.error == nil else { continue }
            ids.insert(row.id)
        }
        return ids
    }

    /// One answer, in the harness's run format (ModerationVectors::Judgment, plus a few fields it ignores).
    public struct Row: Codable, Sendable, Hashable {
        public var id: String
        public var outcome: String?
        public var resolution: String?
        public var confidence: Double?
        /// "logits" when `confidence` came from the outcome's raw probabilities, "stated" when it's the model's number.
        public var confidenceSource: String?
        public var statedConfidence: Double?
        /// The four outcomes' probabilities, renormalised over the four.
        public var outcomeProbabilities: [String: Double]?
        /// How much of the whole raw distribution the four outcomes held (low means the model wanted to write
        /// something else).
        public var outcomeCoverage: Double?
        public var category: String?
        public var playbook: String?
        public var staffAlert: Bool?
        public var emergencyServicesFirst: Bool?
        public var glamReply: String?
        public var reason: String?
        public var model: String?
        public var latencyMs: Int?
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var error: String?

        enum CodingKeys: String, CodingKey {
            case id, outcome, resolution, confidence, category, playbook, reason, model, error
            case confidenceSource = "confidence_source", statedConfidence = "stated_confidence"
            case outcomeProbabilities = "outcome_probabilities", outcomeCoverage = "outcome_coverage"
            case staffAlert = "staff_alert", emergencyServicesFirst = "emergency_services_first"
            case glamReply = "glam_reply", latencyMs = "latency_ms", inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        public init(id: String, error: String? = nil) { self.id = id; self.error = error }

        /// The row as one JSON line, keys sorted, nils left out.
        public var jsonLine: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? #"{"id":"\#(id)"}"#
        }
    }

    /// Reads the model's reply into a row. `probabilities` are the outcomes' raw probabilities at the outcome position
    /// (nil when they couldn't be read); a hold's resolution is kept only on a hold, as the harness does.
    public static func row(id: String, reply: String, probabilities: [String: Double]?) -> Row {
        var row = Row(id: id)
        guard let object = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any] else {
            row.error = "unusable answer: \(reply.prefix(200))"
            return row
        }
        guard let outcome = (object["outcome"] as? String)?.lowercased(), outcomes.contains(outcome) else {
            row.error = "unknown outcome \(String(describing: object["outcome"]))"
            return row
        }
        row.outcome = outcome
        if outcome == "hold", let resolution = object["hold_resolution"] as? String, resolutions.contains(resolution) {
            row.resolution = resolution
        }
        row.category = object["category"] as? String
        row.playbook = object["playbook"] as? String
        row.staffAlert = object["staff_alert"] as? Bool
        row.emergencyServicesFirst = object["emergency_services_first"] as? Bool
        row.glamReply = object["glam_reply"] as? String ?? ""
        row.reason = object["reason"] as? String
        if let stated = object["confidence"] as? Double { row.statedConfidence = min(max(stated, 0), 1) }
        if let probabilities, let (shares, coverage) = normalised(probabilities), let share = shares[outcome] {
            row.outcomeProbabilities = shares
            row.outcomeCoverage = rounded(coverage)
            row.confidence = share
            row.confidenceSource = "logits"
        } else if let stated = row.statedConfidence {
            row.confidence = stated
            row.confidenceSource = "stated"
        }
        return row
    }

    /// The outcomes' raw probabilities renormalised over the outcomes, and the share of the whole distribution they
    /// held; nil when they held none.
    public static func normalised(_ probabilities: [String: Double]) -> (shares: [String: Double], coverage: Double)? {
        let coverage = outcomes.reduce(0) { $0 + max(probabilities[$1] ?? 0, 0) }
        guard coverage > 0 else { return nil }
        return (outcomes.reduce(into: [:]) { $0[$1] = rounded(max(probabilities[$1] ?? 0, 0) / coverage) }, coverage)
    }

    private static func rounded(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}
