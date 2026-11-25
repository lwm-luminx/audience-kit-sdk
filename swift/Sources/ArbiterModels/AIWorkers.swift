import Foundation

// The console's Workers page (api doc/AI_WORKERS.md): for each of an audience's AI workers, whether it works, when,
// on which provider and with which MCP tools. The Mac reads it from `chat { moderation { settings } }` under
// `workers`. The server already keeps each worker to its MCP tools and hands out research work only inside its hours;
// pausing the AI host and moderation outside theirs, and how often research looks for work, are the Mac's to do.

/// One of an audience's AI workers, by its key on the API (AI::Workers::CATALOG).
public enum AIWorkerKey: String, CaseIterable, Sendable, Hashable, Codable {
    /// The AI host (Glam on Hot Mess): answers in the chat rooms.
    case glam
    /// The guard and the moderation rules on each chat message.
    case moderation
    /// Researches suggestions from the evaluation queue.
    case research

    /// The name the console gives it.
    public var name: String {
        switch self {
        case .glam: "AI host"
        case .moderation: "Moderation"
        case .research: "Research"
        }
    }

    /// The value of the `X-AudienceKit-Worker` header on its MCP calls, so the server gives it only its own tools.
    public var header: String { rawValue }
}

/// When a worker works (AI::WorkerSchedule): always, or hours on chosen days in a time zone, and how often it looks
/// for work.
public struct AIWorkerSchedule: Codable, Sendable, Hashable {
    /// `always` or `hours`.
    public var mode: String
    /// The days its hours start on, 0 (Sunday) to 6.
    public var days: [Int]
    /// HH:MM. An end before the start runs overnight and belongs to the day it starts on; the same time for both is the
    /// whole day.
    public var start: String
    public var end: String
    /// An IANA name; one the Mac doesn't know reads as UTC, as on the server.
    public var timeZone: String
    /// How often it looks for work, or nil for as soon as there is some.
    public var everyMinutes: Int?

    public init(mode: String = "always", days: [Int] = Array(0...6), start: String = "00:00", end: String = "00:00",
                timeZone: String = "Etc/UTC", everyMinutes: Int? = nil) {
        self.mode = mode; self.days = days; self.start = start; self.end = end; self.timeZone = timeZone
        self.everyMinutes = everyMinutes
    }

    private enum CodingKeys: String, CodingKey { case mode, days, start, end, timeZone, everyMinutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AIWorkerSchedule()
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? defaults.mode
        days = (try? c.decodeIfPresent([Int].self, forKey: .days)) ?? defaults.days
        start = (try? c.decodeIfPresent(String.self, forKey: .start)) ?? defaults.start
        end = (try? c.decodeIfPresent(String.self, forKey: .end)) ?? defaults.end
        timeZone = (try? c.decodeIfPresent(String.self, forKey: .timeZone)) ?? defaults.timeZone
        everyMinutes = try? c.decodeIfPresent(Int.self, forKey: .everyMinutes)
    }

    public var always: Bool { mode != "hours" }

    /// Whether the moment falls inside it, worked out as the server does (AI::WorkerSchedule#cover?).
    public func covers(_ date: Date) -> Bool {
        if always { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = (parts.weekday ?? 1) - 1
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let from = Self.minutes(start), to = Self.minutes(end)
        if from == to { return days.contains(weekday) }
        if from < to { return days.contains(weekday) && minute >= from && minute < to }
        return (days.contains(weekday) && minute >= from) || (days.contains((weekday + 6) % 7) && minute < to)
    }

    static func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").map { Int($0) ?? 0 }
        return (parts.first ?? 0) * 60 + (parts.dropFirst().first ?? 0)
    }

    /// How often to look for work, when set.
    public var every: Duration? { everyMinutes.flatMap { $0 > 0 ? .seconds($0 * 60) : nil } }
}

/// One worker as the console set it, as the Mac reads it.
public struct AIWorkerSettings: Codable, Sendable, Hashable {
    /// The provider value for the models on this Mac.
    public static let onDevice = "device"

    public var enabled: Bool
    /// Whether the server counted it working when the settings were read; the Mac works it out again from `schedule`
    /// between reads.
    public var workingNow: Bool?
    public var schedule: AIWorkerSchedule?
    /// `device`, or the key of a provider the audience linked (openai, anthropic, google, openrouter).
    public var provider: String?
    public var model: String?
    /// The MCP tools it may call.
    public var tools: [String]?
    public var prompts: [String]?
    public var updatedAt: String?

    public init(enabled: Bool = true, workingNow: Bool? = nil, schedule: AIWorkerSchedule? = nil,
                provider: String? = nil, model: String? = nil, tools: [String]? = nil, prompts: [String]? = nil,
                updatedAt: String? = nil) {
        self.enabled = enabled; self.workingNow = workingNow; self.schedule = schedule; self.provider = provider
        self.model = model; self.tools = tools; self.prompts = prompts; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, workingNow, schedule, provider, model, tools, prompts, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        workingNow = try? c.decodeIfPresent(Bool.self, forKey: .workingNow)
        schedule = try? c.decodeIfPresent(AIWorkerSchedule.self, forKey: .schedule)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        tools = try? c.decodeIfPresent([String].self, forKey: .tools)
        prompts = try? c.decodeIfPresent([String].self, forKey: .prompts)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Whether it works at that moment: on, and inside its hours.
    public func working(at date: Date = Date()) -> Bool {
        guard enabled else { return false }
        if let schedule { return schedule.covers(date) }
        return workingNow ?? true
    }

    /// Whether it runs on this Mac's own models.
    public var onDevice: Bool { (provider ?? Self.onDevice) == Self.onDevice }

    /// Where it stands, for Settings: "working", "off in the console", "outside its hours", and a cloud provider the Mac
    /// can't call yet.
    public func line(_ key: AIWorkerKey, at date: Date = Date()) -> String {
        var parts = [key.name + ": " + (!enabled ? "off in the console" : working(at: date) ? "working" : "outside its hours")]
        if enabled, let every = schedule?.everyMinutes, key == .research { parts.append("checks every \(every) min") }
        if !onDevice, let provider {
            parts.append("set to \(provider)\(model.map { " (\($0))" } ?? ""), runs on this Mac's models for now")
        }
        return parts.joined(separator: " · ")
    }
}

extension ServerEngineSettings {
    /// The worker as the console set it; nil from an API before the Workers page.
    public func worker(_ key: AIWorkerKey) -> AIWorkerSettings? { workers?[key.rawValue] }

    /// Whether the worker works at that moment; one the API doesn't describe always does.
    public func working(_ key: AIWorkerKey, at date: Date = Date()) -> Bool {
        worker(key)?.working(at: date) ?? true
    }
}

extension Optional where Wrapped == ServerEngineSettings {
    /// Whether the worker works at that moment; with no console settings read yet, it does.
    public func working(_ key: AIWorkerKey, at date: Date = Date()) -> Bool {
        self?.working(key, at: date) ?? true
    }
}
