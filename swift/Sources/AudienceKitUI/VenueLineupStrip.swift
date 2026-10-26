#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

/// What the "+" at the end of the lineup adds (Rick, 2026-10-26): the attendee's karaoke signup, or a song request
/// for the DJ. It always sits after the last entry, on an empty lineup too, mirroring the lineup editor. While the
/// venue takes them it opens the flow (`action`); once they're closed for the night (closed early, or past the
/// cutoff) a "Signups closed" marker stands in its place; otherwise (nobody on to take them yet) the "+" is greyed
/// with the reason.
public struct LineupAddition: Identifiable {
    public enum Kind: String, Sendable { case karaoke, song }

    public let kind: Kind
    public let window: SongRequestWindow
    public let action: () -> Void

    public var id: String { kind.rawValue }

    public init(kind: Kind, window: SongRequestWindow, action: @escaping () -> Void) {
        self.kind = kind
        self.window = window
        self.action = action
    }

    /// Karaoke signups' "+", when the venue runs AudienceKit karaoke tonight.
    public static func karaoke(_ lineup: VenueLineup, action: @escaping () -> Void) -> LineupAddition? {
        guard let window = lineup.karaoke, window.permitted,
              !(lineup.karaokeSession?.isPartnerSessionTonight ?? false) else { return nil }
        return LineupAddition(kind: .karaoke, window: window, action: action)
    }

    /// Song requests' "+", when the venue takes them.
    public static func songRequests(_ lineup: VenueLineup, action: @escaping () -> Void) -> LineupAddition? {
        guard let window = lineup.songRequests, window.permitted else { return nil }
        return LineupAddition(kind: .song, window: window, action: action)
    }

    /// "Sign up to sing" or "Request a song".
    var label: String { kind == .karaoke ? String(localized: "Sign up to sing") : String(localized: "Request a song") }
    /// "Signups closed" or "Requests closed".
    var closedLabel: String { kind == .karaoke ? String(localized: "Signups closed") : String(localized: "Requests closed") }
    var symbol: String { kind == .karaoke ? "music.mic" : "music.note" }
}

/// Tonight's lineup of everyone who isn't a karaoke singer, as a horizontal strip in running order: hosts, DJs,
/// performers, MCs and intermissions, then the "+" (``LineupAddition``). The act on now is scrolled into view (the
/// one before it mostly off the leading edge), both edges fade, and it follows as the venue advances. A lineup of only
/// hosts isn't a running order: it shows "Hosted by A and B", side by side in billing order, all on together. At
/// accessibility text sizes it becomes a list. The karaoke singers are ``KaraokeQueue``'s.
public struct VenueLineupStrip: View {
    private let entries: [LineupEntry]
    private let upNextID: String?
    private let title: String?
    private let timeZone: TimeZone
    private let additions: [LineupAddition]
    private let onSelect: ((LineupEntry) -> Void)?
    private let onSelectPerson: ((LineupEntry.Person) -> Void)?

    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - entries: the whole running order; singers are left out here.
    ///   - upNextID: what advancing puts on next.
    ///   - title: the heading; nil hides it.
    ///   - timeZone: the venue's, for set times.
    ///   - additions: the "+" at the end (karaoke signups, song requests); none leaves it out.
    ///   - onSelect: called when an act is tapped, e.g. to open its person.
    ///   - onSelectPerson: called when one host of a hosts-only lineup is tapped; defaults to `onSelect` with the
    ///     host's entry.
    public init(entries: [LineupEntry], upNextID: String?, title: String? = String(localized: "Tonight's lineup"),
                timeZone: TimeZone = .current, additions: [LineupAddition] = [],
                onSelect: ((LineupEntry) -> Void)? = nil, onSelectPerson: ((LineupEntry.Person) -> Void)? = nil) {
        self.entries = entries
        self.upNextID = upNextID
        self.title = title
        self.timeZone = timeZone
        self.additions = additions
        self.onSelect = onSelect
        self.onSelectPerson = onSelectPerson
    }

    /// The strip for a venue's lineup.
    public init(lineup: VenueLineup, title: String? = String(localized: "Tonight's lineup"),
                timeZone: TimeZone = .current, additions: [LineupAddition] = [],
                onSelect: ((LineupEntry) -> Void)? = nil, onSelectPerson: ((LineupEntry.Person) -> Void)? = nil) {
        self.init(entries: lineup.entries, upNextID: lineup.upNextID, title: title, timeZone: timeZone,
                  additions: additions, onSelect: onSelect, onSelectPerson: onSelectPerson)
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var acts: [LineupEntry] { entries.filter { !$0.isSinger } }
    /// The hosts, when the lineup is nothing but hosts (and MCs): no running order to show.
    private var hostsOnly: [LineupEntry]? {
        let hosts = acts.filter { $0.kind == .act && ($0.role == .host || $0.role == .mc) && $0.state != .done }
        return !hosts.isEmpty && acts.allSatisfy { $0.kind == .act && ($0.role == .host || $0.role == .mc) } ? hosts : nil
    }
    /// Its hosts' people in billing order, each once.
    private var hostPeople: [(entry: LineupEntry, person: LineupEntry.Person?)] {
        var seen = Set<String>()
        return (hostsOnly ?? []).flatMap { entry -> [(entry: LineupEntry, person: LineupEntry.Person?)] in
            entry.people.isEmpty ? [(entry, nil)] : entry.people.filter { seen.insert($0.id).inserted }.map { (entry, $0) }
        }
    }

    /// Where the strip rests: the first entry on now, else the first still to come, else the last.
    private var anchorID: String? {
        (acts.first { $0.state == .on } ?? acts.first { $0.state == .upcoming } ?? acts.last)?.id
    }

    public var body: some View {
        if !acts.isEmpty || !additions.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                if let title {
                    Text(title).font(TokenFont.heading).foregroundStyle(Color(colors.ink))
                        .padding(.horizontal, DesignTokens.Spacing.s4).accessibilityAddTraits(.isHeader)
                }
                if hostsOnly != nil {
                    Text(hostedBy).font(TokenFont.subheading).foregroundStyle(Color(colors.ink))
                        .padding(.horizontal, DesignTokens.Spacing.s4)
                }
                if typeSize.isAccessibilitySize { rows } else { strip }
            }
        }
    }

    /// "Hosted by Darcy and Anya".
    private var hostedBy: String {
        let names = hostPeople.map { $0.person?.name ?? $0.entry.displayName }.filter { !$0.isEmpty }
        return String(localized: "Hosted by \(names.formatted(.list(type: .and)))")
    }

    private func select(_ entry: LineupEntry, _ person: LineupEntry.Person?) -> (() -> Void)? {
        if let person, let onSelectPerson { return { onSelectPerson(person) } }
        guard let onSelect else { return nil }
        return { onSelect(entry) }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.s2) {
                    if hostsOnly != nil {
                        ForEach(Array(hostPeople.enumerated()), id: \.offset) { _, host in
                            HostChip(entry: host.entry, person: host.person, onSelect: select(host.entry, host.person))
                        }
                    } else {
                        ForEach(acts) { entry in
                            Group {
                                if entry.kind == .intermission { IntermissionChip(entry: entry, isUpNext: entry.id == upNextID) }
                                else { card(entry) }
                            }
                            .id(entry.id)
                        }
                    }
                    ForEach(additions) { AdditionTile(addition: $0) }
                }
                .padding(.horizontal, DesignTokens.Spacing.s8)
            }
            .mask(EdgeFade())
            .onAppear { if let anchorID { proxy.scrollTo(anchorID, anchor: .leading) } }
            .onChange(of: anchorID) { id in
                guard let id else { return }
                if reduceMotion { proxy.scrollTo(id, anchor: .leading) }
                else { withAnimation(.easeInOut) { proxy.scrollTo(id, anchor: .leading) } }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if hostsOnly != nil {
                ForEach(Array(hostPeople.enumerated()), id: \.offset) { _, host in
                    HostChip(entry: host.entry, person: host.person, onSelect: select(host.entry, host.person), asRow: true)
                        .padding(.horizontal, DesignTokens.Spacing.s4)
                }
            } else {
                ForEach(acts) { entry in
                    ActRow(entry: entry, isUpNext: entry.id == upNextID, timeZone: timeZone)
                        .padding(.horizontal, DesignTokens.Spacing.s4)
                }
            }
            ForEach(additions) { AdditionTile(addition: $0, asRow: true).padding(.horizontal, DesignTokens.Spacing.s4) }
        }
    }

    @ViewBuilder
    private func card(_ entry: LineupEntry) -> some View {
        if let onSelect, entry.kind == .act {
            Button { onSelect(entry) } label: { ActCard(entry: entry, isUpNext: entry.id == upNextID, timeZone: timeZone) }
                .buttonStyle(.plain)
        } else {
            ActCard(entry: entry, isUpNext: entry.id == upNextID, timeZone: timeZone)
        }
    }
}

/// One host of a hosts-only lineup: their avatar and name, side by side with the others, all on together. No card,
/// since a card reads as a slot in a running order.
struct HostChip: View {
    let entry: LineupEntry
    let person: LineupEntry.Person?
    let onSelect: (() -> Void)?
    var asRow = false
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    private var name: String { person?.name ?? entry.displayName }

    var body: some View {
        if let onSelect {
            Button(action: onSelect) { content }.buttonStyle(.plain).accessibilityAddTraits(.isLink)
        } else {
            content
        }
    }

    private var content: some View {
        let colors = preset.colors(scheme)
        let avatar = AudienceAvatar(url: person?.avatarUrl.flatMap(URL.init(string:)), name: name,
                                    size: asRow ? 44 : DesignTokens.Size.avatarLg)
        return Group {
            if asRow {
                HStack(spacing: DesignTokens.Spacing.s3) {
                    avatar
                    Text(name).font(TokenFont.subheading).foregroundStyle(Color(colors.ink))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DesignTokens.Spacing.s2)
            } else {
                VStack(spacing: DesignTokens.Spacing.s1 + 2) {
                    avatar
                    Text(name).font(TokenFont.label).lineLimit(2).multilineTextAlignment(.center)
                        .foregroundStyle(Color(colors.ink))
                }
                .frame(width: 88)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([name, String(localized: "Host"), entry.state == .on ? String(localized: "on now") : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

/// The "+" at the end of the lineup (``LineupAddition``): open, greyed with the reason while nobody's on to take
/// them, or a "Signups closed" marker once they're closed for the night.
struct AdditionTile: View {
    let addition: LineupAddition
    var asRow = false
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    private var window: SongRequestWindow { addition.window }
    private var reason: String? { window.closedReason.flatMap { $0.isEmpty ? nil : $0 } }

    var body: some View {
        if window.closed { closedMarker } else { plus }
    }

    private var plus: some View {
        let colors = preset.colors(scheme)
        let open = window.open
        return Button(action: addition.action) {
            layout(symbol: "plus", title: addition.label, detail: open ? nil : reason,
                   ink: open ? colors.accentInk : colors.inkMuted)
                .background(Color(open ? colors.accentSoft : colors.surfaceSunken), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(open ? colors.accent : colors.border), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
        }
        .buttonStyle(.plain).disabled(!open)
        .accessibilityLabel(addition.label)
        .accessibilityValue(open ? "" : (reason ?? ""))
    }

    private var closedMarker: some View {
        let colors = preset.colors(scheme)
        return layout(symbol: "lock.fill", title: addition.closedLabel,
                      detail: addition.kind == .karaoke ? String(localized: "Everyone on the list still sings") : nil,
                      ink: colors.inkMuted)
            .background(Color(colors.surfaceSunken), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }

    private func layout(symbol: String, title: String, detail: String?, ink: RGBAColor) -> some View {
        let colors = preset.colors(scheme)
        return Group {
            if asRow {
                HStack(spacing: DesignTokens.Spacing.s3) {
                    Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Color(ink)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(TokenFont.subheading).foregroundStyle(Color(ink))
                        if let detail { Text(detail).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted)) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(DesignTokens.Spacing.s3)
            } else {
                VStack(spacing: DesignTokens.Spacing.s1 + 2) {
                    Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(Color(ink))
                        .frame(width: DesignTokens.Size.avatarLg, height: DesignTokens.Size.avatarLg)
                    Text(title).font(TokenFont.label).multilineTextAlignment(.center).lineLimit(2).foregroundStyle(Color(ink))
                    if let detail {
                        Text(detail).font(TokenFont.caption).multilineTextAlignment(.center).lineLimit(3)
                            .foregroundStyle(Color(colors.inkMuted))
                    }
                }
                .padding(DesignTokens.Spacing.s3)
                .frame(width: 140)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

/// Fades the strip out over its first and last 40 points.
private struct EdgeFade: View {
    var body: some View {
        GeometryReader { geometry in
            let fade = min(40 / max(geometry.size.width, 1), 0.5)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: fade),
                                   .init(color: .black, location: 1 - fade), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// An act's card in the strip.
struct ActCard: View {
    let entry: LineupEntry
    let isUpNext: Bool
    let timeZone: TimeZone
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var done: Bool { entry.state == .done }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s1 + 2) {
            Avatars(entry: entry).opacity(done ? 0.5 : 1)
            Text(entry.displayName).font(TokenFont.subheading).multilineTextAlignment(.center).lineLimit(2)
                .foregroundStyle(Color(done ? colors.inkMuted : colors.ink))
            if let role = RoleLabel(entry.role) {
                Label(role.title, systemImage: role.symbol).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            }
            if let time = LineupTime.text(entry, timeZone: timeZone) {
                Text(time).font(TokenFont.bodySm).monospacedDigit().foregroundStyle(Color(colors.inkMuted))
            }
            StatusBadge(entry: entry, isUpNext: isUpNext).frame(height: 20)
        }
        .padding(DesignTokens.Spacing.s3)
        .frame(width: 140)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(done ? colors.surfaceSunken : colors.surfaceRaised),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay { if !done { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(colors.border)) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LineupAccessibility.act(entry, isUpNext: isUpNext, timeZone: timeZone))
    }
}

/// An act as a row, for accessibility text sizes.
struct ActRow: View {
    let entry: LineupEntry
    let isUpNext: Bool
    let timeZone: TimeZone
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    private var colors: DesignTokens.Colors { preset.colors(scheme) }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s3) {
            Avatars(entry: entry, size: 44).opacity(entry.state == .done ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(TokenFont.subheading)
                    .foregroundStyle(Color(entry.state == .done ? colors.inkMuted : colors.ink))
                if let role = RoleLabel(entry.role) {
                    Label(role.title, systemImage: role.symbol).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                }
                if let time = LineupTime.text(entry, timeZone: timeZone) {
                    Text(time).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s2)
            StatusBadge(entry: entry, isUpNext: isUpNext)
        }
        .padding(.vertical, DesignTokens.Spacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LineupAccessibility.act(entry, isUpNext: isUpNext, timeZone: timeZone))
    }
}

/// An intermission in the strip: a chip, green while it's on.
struct IntermissionChip: View {
    let entry: LineupEntry
    let isUpNext: Bool
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    private var colors: DesignTokens.Colors { preset.colors(scheme) }

    var body: some View {
        let on = entry.state == .on, done = entry.state == .done
        VStack(spacing: DesignTokens.Spacing.s1) {
            Label(entry.displayName, systemImage: on ? "waveform" : "cup.and.saucer")
                .font(TokenFont.label).lineLimit(1)
                .foregroundStyle(Color(on ? colors.success : done ? colors.inkMuted : colors.ink))
                .padding(.horizontal, DesignTokens.Spacing.s3).frame(minHeight: 44)
                .background(Color(on ? colors.successSoft : done ? colors.surfaceSunken : colors.controlFill),
                            in: Capsule())
            if isUpNext && !on {
                UpNextBadge()
            }
        }
        .frame(maxWidth: 140, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([entry.displayName, String(localized: "intermission"),
                             on ? String(localized: "on now") : isUpNext ? String(localized: "up next")
                                 : done ? String(localized: "done") : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

/// An entry's people: one avatar, or the first two of a duet overlapping.
struct Avatars: View {
    let entry: LineupEntry
    var size: CGFloat = DesignTokens.Size.avatarLg

    var body: some View {
        let people = Array(entry.people.prefix(2))
        if people.count > 1 {
            HStack(spacing: -12) {
                ForEach(people) { person in
                    AudienceAvatar(url: person.avatarUrl.flatMap(URL.init(string:)), name: person.name ?? "",
                                   size: DesignTokens.Size.avatarMd)
                }
            }
            .frame(height: size)
        } else {
            AudienceAvatar(url: people.first?.avatarUrl.flatMap(URL.init(string:)), name: entry.displayName, size: size)
        }
    }
}

/// On now, Up next or Done, for an act.
struct StatusBadge: View {
    let entry: LineupEntry
    let isUpNext: Bool
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        switch entry.state {
        case .on:
            Pill(text: String(localized: "On now"), symbol: "waveform", ink: colors.success, fill: colors.successSoft)
        case .done:
            Text(String(localized: "Done")).font(TokenFont.caption).foregroundStyle(Color(colors.inkMuted))
        default:
            if isUpNext { UpNextBadge() }
        }
    }
}

/// A small rounded badge.
struct Pill: View {
    let text: String
    let symbol: String?
    let ink: RGBAColor
    let fill: RGBAColor

    var body: some View {
        Label { Text(text) } icon: { if let symbol { Image(systemName: symbol) } }
            .font(TokenFont.caption).labelStyle(.titleAndIcon)
            .foregroundStyle(Color(ink))
            .padding(.horizontal, DesignTokens.Spacing.s2).padding(.vertical, 2)
            .background(Color(fill), in: Capsule())
    }
}

/// A role's label and symbol.
struct RoleLabel {
    let title: String
    let symbol: String

    init?(_ role: LineupEntry.Role?) {
        switch role {
        case .host: (title, symbol) = (String(localized: "Host"), "sparkles")
        case .dj: (title, symbol) = (String(localized: "DJ"), "headphones")
        case .performer: (title, symbol) = (String(localized: "Performer"), "theatermasks")
        case .mc: (title, symbol) = (String(localized: "MC"), "music.mic")
        case .singer: (title, symbol) = (String(localized: "Singer"), "music.mic")
        default: return nil
        }
    }
}

/// An act's set time, shown only when it has a hard start: "8:00 PM", "8:00 PM – close", "8:00 – 9:00 PM".
enum LineupTime {
    static func text(_ entry: LineupEntry, timeZone: TimeZone) -> String? {
        guard entry.startTiming == .hard, let start = entry.startsAt else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        switch entry.endTiming {
        case .close: return "\(start.formatted(style)) – \(String(localized: "close"))"
        case .time:
            guard let end = entry.endsAt else { return start.formatted(style) }
            return "\(start.formatted(style)) – \(end.formatted(style))"
        default: return start.formatted(style)
        }
    }
}

/// What VoiceOver says for an act: "Trixie, Host, 8 PM to close, on now".
enum LineupAccessibility {
    static func act(_ entry: LineupEntry, isUpNext: Bool, timeZone: TimeZone) -> String {
        let state: String? = switch entry.state {
        case .on: String(localized: "on now")
        case .done: String(localized: "done")
        default: isUpNext ? String(localized: "up next") : nil
        }
        return [entry.displayName, RoleLabel(entry.role)?.title, LineupTime.text(entry, timeZone: timeZone), state]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
#endif
