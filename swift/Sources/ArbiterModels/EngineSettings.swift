import Foundation

/// What the engine runs and how, as Settings edits it. The Mac app keeps it; the iPad app has no engine.
public struct EngineSettings: Codable, Sendable, Hashable {
    /// Which model judges the moderation rules: the small guard (fast) or the decisions model.
    public enum RulesModel: String, Codable, Sendable { case guardModel = "guard", decisions }

    /// The GGUF for decisions and Glam (Gemma 4 when found).
    public var modelPath: String?
    /// The GGUF for the guard and, by default, the rules (ShieldGemma 2B Q8_0 when found).
    public var guardModelPath: String?
    /// The GGUF that turns text into vectors (one of Garage's embedding models, `EmbeddingCatalog`); nil until one is
    /// found or picked. Optional, so settings saved before it still decode.
    public var embeddingModelPath: String?
    /// The conformal sets' error rate: lower makes more answers unsure.
    public var alpha: Double
    /// Under this share of the answer position on true/false, a check is unscored and goes to a person.
    public var coverageThreshold: Double
    /// Per guard policy, the score at which it flags.
    public var guardThresholds: [String: Double]
    public var rulesEnabled: Bool
    public var rulesModel: RulesModel
    public var venueRating: VenueRating
    /// Per rule and rating, overriding the seed thresholds.
    public var ruleThresholds: [String: [VenueRating: Double]]
    public var glamMode: GlamMode
    /// What the AI host is called in this audience (the console's; Glam unless set). Optional so settings saved before
    /// it still decode; `host` reads it.
    public var hostName: String?
    /// What "Re-show guidelines" posts.
    public var roomGuidelines: String
    /// The evaluation types the worker takes.
    public var evaluationTypes: [String]
    public var autoStartWorker: Bool
    public var autoStartGlam: Bool
    /// Which configuration Glam's runs belong to: nil is the default, a name is a variant to compare against it. The
    /// API numbers each configuration's runs on a message, and the newest run of the default is the one that counts.
    public var configuration: String?
    /// The prompts the API serves for the audience (MCP `prompts/get`), as last fetched; nil, or a name missing from
    /// it, uses the text built into the engine. Never saved with the Mac's own settings: each audience link fills it.
    public var prompts: ArbiterPromptSet?
    /// Whether the audience has Glam's fast lane on (the console's `hosting` AI capability): the backend hosts the
    /// rooms and this Mac reviews what it did instead of hosting them itself. Only ever from the API.
    public var glamFastLane: Bool?

    /// Whether this Mac reviews the fast lane rather than hosting.
    public var reviewsFastLane: Bool { glamFastLane == true }

    /// The AI host's name: Glam unless the audience named its own.
    public var host: String {
        guard let name = hostName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return EngineSettings.defaultHost
        }
        return name
    }

    /// The host's name when an audience hasn't set one.
    public static let defaultHost = "Glam"

    /// The configuration trimmed, with blank meaning the default.
    public var configurationName: String? {
        guard let name = configuration?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    public init(modelPath: String? = nil, guardModelPath: String? = nil, alpha: Double = 0.1,
                coverageThreshold: Double = 0.5, guardThresholds: [String: Double] = [:], rulesEnabled: Bool = true,
                rulesModel: RulesModel = .guardModel, venueRating: VenueRating = .adult,
                ruleThresholds: [String: [VenueRating: Double]] = [:], glamMode: GlamMode = .shadow,
                roomGuidelines: String = "", evaluationTypes: [String] = EngineSettings.defaultEvaluationTypes,
                autoStartWorker: Bool = false, autoStartGlam: Bool = false, configuration: String? = nil,
                hostName: String? = nil, prompts: ArbiterPromptSet? = nil, embeddingModelPath: String? = nil) {
        self.modelPath = modelPath; self.guardModelPath = guardModelPath; self.alpha = alpha
        self.embeddingModelPath = embeddingModelPath
        self.coverageThreshold = coverageThreshold; self.guardThresholds = guardThresholds
        self.rulesEnabled = rulesEnabled; self.rulesModel = rulesModel; self.venueRating = venueRating
        self.ruleThresholds = ruleThresholds; self.glamMode = glamMode; self.roomGuidelines = roomGuidelines
        self.evaluationTypes = evaluationTypes; self.autoStartWorker = autoStartWorker; self.autoStartGlam = autoStartGlam
        self.configuration = configuration; self.hostName = hostName; self.prompts = prompts
    }
}

/// GGUF files found on this Mac, with the best pick for each role.
public struct FoundModels: Codable, Sendable, Hashable {
    public let decisions: String?
    public let guardModel: String?
    public let all: [String]
    /// The best embedding model found: one on Garage's list (`EmbeddingCatalog`), its featured picks first.
    public let embedding: String?

    public init(decisions: String?, guardModel: String?, all: [String], embedding: String? = nil) {
        self.decisions = decisions; self.guardModel = guardModel; self.all = all; self.embedding = embedding
    }
}

/// What an audience's admins set for Arbiter in the admin console (Plugins → Moderation, Arbiter as its provider), read
/// on the audience's worker token at `chat { moderation { settings } }`. Only what someone set is there; anything else
/// keeps the Mac's own value, so a Mac set up before these existed works the same until an admin sets them. Which
/// models the Mac runs, whether it starts on launch and its configuration stay the Mac's.
public struct ServerEngineSettings: Codable, Sendable, Hashable {
    /// Whether anyone has set anything for this audience yet.
    public var configured: Bool
    public var updatedAt: String?
    /// When the audience's own prompts last changed in the console, so the Mac knows to fetch them again.
    public var promptsUpdatedAt: String?
    public var glamMode: GlamMode?
    /// What the AI host is called in this audience.
    public var hostName: String?
    public var roomGuidelines: String?
    public var venueRating: VenueRating?
    public var rulesEnabled: Bool?
    public var rulesModel: EngineSettings.RulesModel?
    public var alpha: Double?
    public var coverageThreshold: Double?
    public var guardThresholds: [String: Double]?
    public var ruleThresholds: [String: [VenueRating: Double]]?
    public var evaluationTypes: [String]?
    /// Each AI worker as the console's Workers page set it (glam, moderation, research), by key; nil from an API
    /// before that page (AIWorkers.swift).
    public var workers: [String: AIWorkerSettings]?
    /// Whether the backend hosts the audience's rooms (Glam's fast lane); nil from an API before it.
    public var glamFastLane: Bool?

    public init(configured: Bool = false, updatedAt: String? = nil, glamMode: GlamMode? = nil,
                roomGuidelines: String? = nil, venueRating: VenueRating? = nil, rulesEnabled: Bool? = nil,
                rulesModel: EngineSettings.RulesModel? = nil, alpha: Double? = nil, coverageThreshold: Double? = nil,
                guardThresholds: [String: Double]? = nil, ruleThresholds: [String: [VenueRating: Double]]? = nil,
                evaluationTypes: [String]? = nil, hostName: String? = nil) {
        self.configured = configured; self.updatedAt = updatedAt; self.glamMode = glamMode; self.hostName = hostName
        self.roomGuidelines = roomGuidelines; self.venueRating = venueRating; self.rulesEnabled = rulesEnabled
        self.rulesModel = rulesModel; self.alpha = alpha; self.coverageThreshold = coverageThreshold
        self.guardThresholds = guardThresholds; self.ruleThresholds = ruleThresholds
        self.evaluationTypes = evaluationTypes
    }

    private enum CodingKeys: String, CodingKey {
        case configured, updatedAt, promptsUpdatedAt, glamMode, roomGuidelines, venueRating, rulesEnabled, rulesModel, alpha,
             coverageThreshold, guardThresholds, ruleThresholds, evaluationTypes, hostName, workers, glamFastLane
    }

    /// Reads each value on its own, so one this Mac doesn't know (a newer Glam mode) is left to the Mac rather than
    /// losing the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configured = (try? c.decodeIfPresent(Bool.self, forKey: .configured)) ?? false
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
        promptsUpdatedAt = try? c.decodeIfPresent(String.self, forKey: .promptsUpdatedAt)
        glamMode = try? c.decodeIfPresent(GlamMode.self, forKey: .glamMode)
        roomGuidelines = try? c.decodeIfPresent(String.self, forKey: .roomGuidelines)
        venueRating = try? c.decodeIfPresent(VenueRating.self, forKey: .venueRating)
        rulesEnabled = try? c.decodeIfPresent(Bool.self, forKey: .rulesEnabled)
        rulesModel = try? c.decodeIfPresent(EngineSettings.RulesModel.self, forKey: .rulesModel)
        alpha = try? c.decodeIfPresent(Double.self, forKey: .alpha)
        coverageThreshold = try? c.decodeIfPresent(Double.self, forKey: .coverageThreshold)
        guardThresholds = try? c.decodeIfPresent([String: Double].self, forKey: .guardThresholds)
        ruleThresholds = try? c.decodeIfPresent([String: [VenueRating: Double]].self, forKey: .ruleThresholds)
        evaluationTypes = try? c.decodeIfPresent([String].self, forKey: .evaluationTypes)
        hostName = try? c.decodeIfPresent(String.self, forKey: .hostName)
        workers = try? c.decodeIfPresent([String: AIWorkerSettings].self, forKey: .workers)
        glamFastLane = try? c.decodeIfPresent(Bool.self, forKey: .glamFastLane)
    }

    /// The settings the console decides, for the Mac's Settings to show as set there.
    public var managed: Set<ManagedSetting> {
        var keys = Set<ManagedSetting>()
        if glamMode != nil { keys.insert(.glamMode) }
        if roomGuidelines != nil { keys.insert(.roomGuidelines) }
        if venueRating != nil { keys.insert(.venueRating) }
        if rulesEnabled != nil { keys.insert(.rulesEnabled) }
        if rulesModel != nil { keys.insert(.rulesModel) }
        if alpha != nil { keys.insert(.alpha) }
        if coverageThreshold != nil { keys.insert(.coverageThreshold) }
        if guardThresholds != nil { keys.insert(.guardThresholds) }
        if ruleThresholds != nil { keys.insert(.ruleThresholds) }
        if evaluationTypes != nil { keys.insert(.evaluationTypes) }
        if hostName != nil { keys.insert(.hostName) }
        return keys
    }
}

/// An engine setting the admin console can decide for an audience.
public enum ManagedSetting: String, Sendable, Hashable, CaseIterable {
    case glamMode, roomGuidelines, venueRating, rulesEnabled, rulesModel, alpha, coverageThreshold, guardThresholds,
         ruleThresholds, evaluationTypes, hostName
}

extension EngineSettings {
    /// The work types a worker takes unless Settings or the console says otherwise: suggestions, and Soapbox articles
    /// weighed for national news.
    public static let defaultEvaluationTypes = ["submission_research", "article_national_feature"]
    /// The default before national news (Arbiter up to 2026-11), which a Mac's saved settings may still hold.
    static let legacyEvaluationTypes = ["submission_research"]

    /// The work types the worker claims: `evaluationTypes`, with the old default read as today's, so a Mac set up
    /// before national news takes that work too without anyone editing its settings.
    public var workTypes: [String] {
        evaluationTypes == Self.legacyEvaluationTypes ? Self.defaultEvaluationTypes : evaluationTypes
    }

    /// These settings with what the audience's admins set in the console in place of the Mac's own. A threshold map the
    /// console set replaces the Mac's whole map: the console keeps the overrides, and the rest are the seed values.
    public func applying(_ server: ServerEngineSettings?) -> EngineSettings {
        guard let server else { return self }
        var settings = self
        if let value = server.glamMode { settings.glamMode = value }
        if let value = server.roomGuidelines { settings.roomGuidelines = value }
        if let value = server.venueRating { settings.venueRating = value }
        if let value = server.rulesEnabled { settings.rulesEnabled = value }
        if let value = server.rulesModel { settings.rulesModel = value }
        if let value = server.alpha { settings.alpha = value }
        if let value = server.coverageThreshold { settings.coverageThreshold = value }
        if let value = server.guardThresholds { settings.guardThresholds = value }
        if let value = server.ruleThresholds { settings.ruleThresholds = value }
        if let value = server.evaluationTypes { settings.evaluationTypes = value }
        if let value = server.hostName { settings.hostName = value }
        settings.glamFastLane = server.glamFastLane
        return settings
    }
}
