import Foundation

/// How `arbiterctl` prints the app's answers for a person (`--json` prints them as they came).
public enum ControlFormat {
    public static func status(_ status: ControlStatus) -> String {
        var lines: [String] = []
        let app = status.app
        lines.append("Arbiter \(app.version) (\(app.build))\(app.debug ? ", Debug build" : "") · pid \(app.pid)")
        var server = "Server: \(status.server.current) (\(status.server.apiURL))"
        if let pending = status.server.pending { server += ", switching to \(pending) on restart" }
        if !status.server.switchable { server += ", fixed for this build" }
        lines.append(server)
        lines.append(account(status.account))
        lines.append("")
        lines.append(engine(status.engine))
        if let background = status.background {
            lines.append("Background: " + [
                background.keepsRunning ? "keeps running with no window" : "quits with its last window",
                background.menuBar ? "menu bar on" : "menu bar off",
                background.opensAtLogin ? "opens at login" : "not a login item",
                background.keepsMacAwake ? "keeps the Mac awake" : "lets the Mac sleep",
            ].joined(separator: ", "))
        }
        lines.append("")
        lines.append(audiences(status.audiences))
        return lines.joined(separator: "\n")
    }

    public static func account(_ account: ControlStatus.Account) -> String {
        var line = account.signedIn ? "Signed in" : "Signed out"
        if account.signedIn {
            line += account.audiences.isEmpty ? ", no audiences" : ": \(account.audiences.count) audience\(account.audiences.count == 1 ? "" : "s")"
            if !account.opened.isEmpty { line += ", open: \(account.opened.joined(separator: ", "))" }
        }
        if account.updateRequired { line += "\n  An update is required before Arbiter can talk to the API." }
        if let error = account.error { line += "\n  Error: \(error)" }
        return line
    }

    public static func engine(_ engine: ControlStatus.Engine) -> String {
        var lines = ["Engine: " + (engine.reviewOnly ? "review only\(engine.reviewOnlyForced ? " (launched with -ArbiterReviewOnly)" : "")"
                                                     : "runs here") + ", Glam mode \(engine.glamMode)"]
        lines.append("  Decisions model: \(name(engine.modelPath))")
        lines.append("  Guard model:     \(name(engine.guardModelPath))")
        lines.append("  Embedding model: \(name(engine.embeddingModelPath))")
        if !engine.downloads.isEmpty {
            lines.append("  Downloads: " + engine.downloads.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        }
        if let error = engine.error { lines.append("  Error: \(error)") }
        return lines.joined(separator: "\n")
    }

    public static func models(_ engine: ControlStatus.Engine) -> String {
        var lines = ["Decisions model: \(engine.modelPath ?? "none")", "Guard model:     \(engine.guardModelPath ?? "none")",
                     "Embedding model: \(engine.embeddingModelPath ?? "none")"]
        lines.append("Folders:")
        lines += engine.modelFolders.isEmpty ? ["  (none picked)"] : engine.modelFolders.map { "  \($0)" }
        lines.append("Found:")
        lines += engine.models.isEmpty ? ["  (none)"] : engine.models.map { "  \($0)" }
        if !engine.downloads.isEmpty {
            lines.append("Downloads:")
            lines += engine.downloads.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }
        }
        return lines.joined(separator: "\n")
    }

    public static func audiences(_ audiences: [ControlStatus.Audience]) -> String {
        guard !audiences.isEmpty else { return "This Mac works for no audience yet." }
        let width = max(8, audiences.map(\.name.count).max() ?? 8)
        var lines = [pad("AUDIENCE", width) + "  " + pad("WORKER", 24) + "  GLAM"]
        for audience in audiences {
            let worker = audience.worker
            var workerText = worker.state + (worker.handled > 0 ? " (\(worker.handled) done)" : "")
            if !worker.running && worker.state != "stopped" { workerText += ", not running" }
            let glam = audience.glam
            var glamText = glam.state
            var extras: [String] = []
            if glam.backlog > 0 { extras.append("\(glam.backlog) waiting") }
            if glam.handled > 0 { extras.append("\(glam.handled) handled") }
            if glam.awaiting > 0 { extras.append("\(glam.awaiting) to approve") }
            if !extras.isEmpty { glamText += " (" + extras.joined(separator: ", ") + ")" }
            lines.append(pad(audience.name + (audience.current ? "*" : ""), width) + "  " + pad(workerText, 24) + "  " + glamText)
            if let message = worker.message, !message.isEmpty { lines.append(pad("", width) + "  worker: \(message)") }
            if let last = worker.last { lines.append(pad("", width) + "  last decision: \(last)") }
            if let message = glam.message, !message.isEmpty { lines.append(pad("", width) + "  \(audience.hostName): \(message)") }
        }
        if audiences.contains(where: \.current) { lines.append("* the audience the window shows") }
        return lines.joined(separator: "\n")
    }

    public static func log(_ line: ControlLogLine, showAudience: Bool) -> String {
        let time = timeFormatter.string(from: Date(timeIntervalSince1970: line.at))
        let source = line.source == .glam ? "glam" : "worker"
        let audience = showAudience ? "[\(line.audience)] " : ""
        return "\(time) \(audience)\(source)\(line.isError ? " ERROR" : ""): \(line.text)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// An embed answer for a person: per input, the vector's width and its first few values.
    public static func embeddings(_ vectors: [[Float]], inputs: [String]) -> String {
        vectors.enumerated().map { index, vector in
            let head = vector.prefix(4).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let text = index < inputs.count ? inputs[index] : "#\(index)"
            let label = text.count > 40 ? String(text.prefix(39)) + "…" : text
            return "\(label): \(vector.count) values [\(head)\(vector.count > 4 ? ", …" : "")]"
        }.joined(separator: "\n")
    }

    private static func name(_ path: String?) -> String {
        guard let path else { return "none chosen" }
        return (path as NSString).lastPathComponent
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
