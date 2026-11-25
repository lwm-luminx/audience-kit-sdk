import Foundation

/// What Arbiter puts on the pasteboard when someone copies a chat message: its words alone, or a report with the
/// room, the times and the lines around it, ready to paste into a bug report (a message out of order, say).
public enum GlamCopyText {
    /// A line as "handle: words", with a rich message's title ahead of its words.
    public static func line(_ line: ChatLine) -> String {
        let words = [line.title, line.text.isEmpty ? nil : line.text].compactMap { $0 }.joined(separator: " · ")
        let who = line.role.map { "\(line.handle) [\($0.rawValue)]" } ?? line.handle
        return "\(who): \(words)"
    }

    /// Every line, oldest first, each with its sent time in UTC; a line sent before the one above it says so,
    /// so a message shown out of order stands out in the paste.
    public static func conversation(_ lines: some Collection<ChatLine>) -> String {
        var previous: Date?
        return lines.map { chatLine in
            var text = line(chatLine)
            if let sent = chatLine.sentAt {
                text = "[\(ArbiterJSON.formatDate(sent))] " + text
                if let previous, sent < previous { text += "  (sent before the line above)" }
                previous = max(previous ?? sent, sent)
            }
            return text
        }
        .joined(separator: "\n")
    }

    /// The judged message's words alone.
    public static func message(_ proposal: GlamProposal) -> String {
        proposal.judged.map { [$0.title, $0.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") } ?? ""
    }

    /// The judged message with where and when it was, what Glam made of it, and the lines before it.
    public static func report(_ proposal: GlamProposal) -> String {
        var parts = ["Room: \(proposal.room.name ?? "A room") (\(proposal.room.kind) \(proposal.room.id))"]
        if let judged = proposal.judged {
            parts.append("Message: \(line(judged))")
            if let sent = judged.sentAt { parts.append("Sent: \(ArbiterJSON.formatDate(sent))") }
        }
        parts.append("Judged: \(ArbiterJSON.formatDate(proposal.at)) (\(source(proposal.mode)))")
        if let cursor = proposal.cursor { parts.append("Feed event: \(cursor)") }
        parts.append("Glam's call: \(proposal.call.tool)")
        if !proposal.lines.isEmpty { parts.append("\nConversation, oldest first:\n" + conversation(proposal.lines)) }
        return parts.joined(separator: "\n")
    }

    /// A message Glam hasn't finished: its words alone.
    public static func message(_ pending: GlamStatus.Pending) -> String { pending.text }

    /// A message Glam hasn't finished, with the room, its time and the lines Glam reads.
    public static func report(_ pending: GlamStatus.Pending) -> String {
        var parts = ["Room: \(pending.room.name ?? "A room") (\(pending.room.kind) \(pending.room.id))",
                     "Message: \(pending.text)",
                     "Sent: \(ArbiterJSON.formatDate(pending.at)) (\(source(pending.source)))",
                     "Glam: \(pending.started == nil ? "queued" : "working on it (\(pending.step ?? "starting"))")"]
        if !pending.lines.isEmpty { parts.append("\nConversation, oldest first:\n" + conversation(pending.lines)) }
        return parts.joined(separator: "\n")
    }

    static func source(_ source: GlamProposal.Source) -> String {
        switch source {
        case .live: "live feed"
        case .replay: "replay"
        case .try: "made up"
        }
    }
}
