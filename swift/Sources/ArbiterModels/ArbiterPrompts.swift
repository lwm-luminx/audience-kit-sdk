import Foundation

/// Which version of a prompt a run used, as the API's templates stamp it (api config/arbiter/prompts, MCP
/// `prompts/get`'s `_meta`). Kept with each run so two prompt versions can be told apart in the record.
public struct PromptStamp: Codable, Sendable, Hashable {
    public let name: String
    public let version: String
    public let digest: String

    public init(name: String, version: String, digest: String) {
        self.name = name; self.version = version; self.digest = digest
    }
}

/// One prompt template from the API, with the server's own variables ({{host_name}}, {{app_name}}) already filled in
/// and the Mac's ({{model}}, {{tool_title}}, …) left for `render`.
public struct ArbiterPrompt: Codable, Sendable, Hashable {
    public let name: String
    public let text: String
    public let version: String
    public let digest: String

    public init(name: String, text: String, version: String, digest: String) {
        self.name = name; self.text = text; self.version = version; self.digest = digest
    }

    public var stamp: PromptStamp { PromptStamp(name: name, version: version, digest: digest) }

    /// The text with each {{name}} replaced by its value; a variable with no value is left as it is.
    public func render(_ values: [String: String] = [:]) -> String {
        values.reduce(text) { text, entry in text.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value) }
    }
}

/// The prompts the API serves for one audience (api doc/MCP.md, "Prompts"), by name. A name the set doesn't have (an
/// API from before templates, or one that couldn't be read) falls back to the text built into the engine, so a Mac is
/// never without a prompt.
public struct ArbiterPromptSet: Codable, Sendable, Hashable {
    public var prompts: [String: ArbiterPrompt]
    /// When the API last changed this audience's own prompts (`promptsUpdatedAt`), as the set was fetched.
    public var updatedAt: String?

    public init(prompts: [String: ArbiterPrompt] = [:], updatedAt: String? = nil) {
        self.prompts = prompts; self.updatedAt = updatedAt
    }

    /// The named prompt rendered with `values`, or nil to use the built-in text.
    public func text(_ name: String, _ values: [String: String] = [:]) -> String? {
        prompts[name].map { $0.render(values) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Every prompt's stamp, by name, for a run's record.
    public var stamps: [PromptStamp] { prompts.values.map(\.stamp).sorted { $0.name < $1.name } }
}
