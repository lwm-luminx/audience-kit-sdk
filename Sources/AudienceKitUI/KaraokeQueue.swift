#if canImport(SwiftUI)
import AudienceKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A venue's karaoke tonight, below ``VenueLineupStrip``. With AudienceKit's own karaoke: the singers in running order
/// (numbered, with their songs, the breaks among them), the signed-in user's signup with Remove, and Sign up to
/// sing. With a partner such as KaraFun: its session's Join link and QR code instead. Nothing fetches here: pass the
/// lineup and run the calls in the closures, then refetch.
public struct KaraokeQueue: View {
    private let lineup: VenueLineup
    private let viewerName: String?
    private let title: String?
    private let previewLimit: Int?
    private let onSeeAll: (() -> Void)?
    private let onSignUp: @MainActor (KaraokeSignup) async throws -> Void
    private let onRemove: @MainActor (SongRequest) async throws -> Void
    private let onSignInNeeded: (() -> Void)?

    @State private var signingUp = false
    @State private var historyShown = false
    @State private var dismissed: Set<String> = []
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    /// - Parameters:
    ///   - lineup: the venue's lineup, from ``AudienceSession/lineup(venueID:)``.
    ///   - viewerName: the signed-in user's name, to sign up as; nil signed out.
    ///   - previewLimit: how many singers to show (the one on stage, up next and after); nil shows them all, with the
    ///     ones who have sung behind a row that opens them. With a limit, "See all" calls `onSeeAll`.
    ///   - onSignUp: signs up (``AudienceSession/signUpToSing(venueID:_:)``); a thrown error shows in the sheet.
    ///   - onRemove: takes a signup back (``AudienceSession/withdrawSongRequest(id:)``).
    ///   - onSignInNeeded: called instead of opening the sheet while signed out, when set.
    public init(lineup: VenueLineup, viewerName: String?, title: String? = String(localized: "Karaoke"),
                previewLimit: Int? = 3, onSeeAll: (() -> Void)? = nil,
                onSignUp: @escaping @MainActor (KaraokeSignup) async throws -> Void,
                onRemove: @escaping @MainActor (SongRequest) async throws -> Void,
                onSignInNeeded: (() -> Void)? = nil) {
        self.lineup = lineup
        self.viewerName = viewerName
        self.title = title
        self.previewLimit = previewLimit
        self.onSeeAll = onSeeAll
        self.onSignUp = onSignUp
        self.onRemove = onRemove
        self.onSignInNeeded = onSignInNeeded
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var window: KaraokeWindow? { lineup.karaoke }
    private var singers: [LineupEntry] { lineup.singers }

    public var body: some View {
        if let session = lineup.karaokeSession, session.provider != nil, !session.isAudienceKit {
            KaraokeJoinSection(session: session, title: title)
        } else if let window, window.permitted || !singers.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                heading
                if let request = featured { card(for: request) }
                if window.permitted && !hasOpenSignup {
                    KaraokeSignupButton(window: window, label: hasSung ? String(localized: "Sing another")
                                                                         : String(localized: "Sign up to sing")) {
                        if viewerName == nil, let onSignInNeeded { onSignInNeeded() } else { signingUp = true }
                    }
                }
                if !singers.isEmpty { list }
                else if window.open {
                    Text(String(localized: "Nobody's on the list yet. Be the first."))
                        .font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s4)
            .sheet(isPresented: $signingUp) {
                KaraokeSignupSheet(viewerName: viewerName, venueName: lineup.venueName,
                                   hostName: window.host?.displayName, submit: onSignUp)
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            if let title { Text(title).font(TokenFont.heading).foregroundStyle(Color(colors.ink)).accessibilityAddTraits(.isHeader) }
            Spacer()
            if !singers.isEmpty {
                Text(singers.count == 1 ? String(localized: "1 singer tonight") : String(localized: "\(singers.count) singers tonight"))
                    .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            }
        }
    }

    private var mine: [SongRequest] { window?.mine ?? [] }
    private var hasOpenSignup: Bool { mine.contains { $0.state.isOpen } }
    private var hasSung: Bool { !mine.isEmpty }

    /// The signup the card shows: the earliest still open, else the latest finished one, until dismissed.
    private var featured: SongRequest? {
        guard let request = lineup.featuredSignup else { return nil }
        return request.state.isOpen || !dismissed.contains(request.id) ? request : nil
    }

    private func card(for request: SongRequest) -> some View {
        let entry = lineup.entry(for: request)
        return MySignupCard(request: request, entry: entry, number: entry.flatMap(lineup.singerNumber(of:)),
                            singersBefore: lineup.singersBefore(request),
                            isUpNext: entry.map { $0.id == lineup.upNextID } ?? false,
                            breakOnNow: lineup.breakOnNow, hostName: window?.host?.displayName,
                            viewerName: viewerName,
                            onRemove: request.state == .queued ? onRemove : nil,
                            onDismiss: request.state.isOpen ? nil : { dismissed.insert(request.id) })
    }

    /// The singers and breaks, sung ones behind a row; with a preview limit, the first few still to come and See all.
    private var list: some View {
        let rows = lineup.karaokeEntries
        let sung = rows.filter { $0.state == .done && $0.isSinger }
        var coming = rows.filter { $0.state != .done }
        let truncated = previewLimit.map { coming.count > $0 } ?? false
        if let previewLimit { coming = Array(coming.prefix(previewLimit)) }
        return VStack(spacing: 0) {
            if previewLimit == nil && !sung.isEmpty {
                Button { withAnimation { historyShown.toggle() } } label: {
                    HStack {
                        Text(sung.count == 1 ? String(localized: "1 has sung") : String(localized: "\(sung.count) have sung"))
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(historyShown ? 180 : 0))
                    }
                    .font(TokenFont.label).foregroundStyle(Color(colors.inkMuted))
                    .padding(.horizontal, DesignTokens.Spacing.s4).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(historyShown ? String(localized: "expanded") : String(localized: "collapsed"))
                Divider().overlay(Color(colors.border))
                if historyShown { ForEach(sung) { row($0); Divider().overlay(Color(colors.border)) } }
            }
            ForEach(Array(coming.enumerated()), id: \.element.id) { index, entry in
                row(entry)
                if index < coming.count - 1 || (truncated && onSeeAll != nil) { Divider().overlay(Color(colors.border)) }
            }
            if truncated, let onSeeAll {
                Button(action: onSeeAll) {
                    HStack {
                        Text(String(localized: "See all \(singers.count) singers"))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(TokenFont.label).foregroundStyle(Color(colors.accentInk))
                    .padding(.horizontal, DesignTokens.Spacing.s4).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(colors.border)) }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func row(_ entry: LineupEntry) -> some View {
        if entry.isSinger {
            SingerRow(entry: entry, number: lineup.singerNumber(of: entry), isUpNext: entry.id == lineup.upNextID)
        } else {
            BreakRow(entry: entry, isUpNext: entry.id == lineup.upNextID)
        }
    }
}

/// One singer: their number, name(s) and song, On stage or Up next, and You on the viewer's own.
struct SingerRow: View {
    let entry: LineupEntry
    let number: Int?
    let isUpNext: Bool
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        let mine = entry.songRequest?.mine ?? false
        let done = entry.state == .done
        HStack(spacing: DesignTokens.Spacing.s3) {
            Text(number.map(String.init) ?? "–").font(TokenFont.subheading).monospacedDigit()
                .foregroundStyle(Color(mine ? colors.accentInk : colors.inkMuted))
                .frame(width: DesignTokens.Size.avatarMd, height: DesignTokens.Size.avatarMd)
                .background(Color(colors.surfaceSunken), in: Circle())
                .overlay { Circle().strokeBorder(Color(mine ? colors.accent : colors.border)) }
                .opacity(done ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignTokens.Spacing.s2) {
                    Text(entry.displayName).font(TokenFont.subheading).lineLimit(1)
                        .foregroundStyle(Color(done ? colors.inkMuted : colors.ink))
                    if mine {
                        Text(String(localized: "You")).font(TokenFont.caption).textCase(.uppercase)
                            .foregroundStyle(Color(colors.onAccent))
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color(colors.accent), in: Capsule())
                    }
                }
                if let song = entry.songRequest?.songLine {
                    Text(song).font(TokenFont.body).lineLimit(1).foregroundStyle(Color(colors.inkMuted))
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s2)
            badge(colors)
        }
        .padding(.horizontal, DesignTokens.Spacing.s4).padding(.vertical, DesignTokens.Spacing.s3)
        .frame(minHeight: 56)
        .background(Color(mine ? colors.accentSoft : done ? colors.surfaceSunken : .init(red: 0, green: 0, blue: 0, alpha: 0)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func badge(_ colors: DesignTokens.Colors) -> some View {
        switch entry.state {
        case .on: Pill(text: String(localized: "On stage"), symbol: "music.mic", ink: colors.success, fill: colors.successSoft)
        case .done:
            Text(entry.songRequest?.state == .skipped ? String(localized: "Passed") : String(localized: "Sang"))
                .font(TokenFont.caption).foregroundStyle(Color(colors.inkMuted))
        default:
            if isUpNext { UpNextBadge() }
        }
    }

    /// "Ada to sing Dancing Queen by ABBA, number 7, up next, you".
    private var label: String {
        let request = entry.songRequest
        let song = [request?.title, request?.artist.map { String(localized: "by \($0)") }].compactMap { $0 }.joined(separator: " ")
        let state: String? = switch entry.state {
        case .on: String(localized: "on stage")
        case .done: request?.state == .skipped ? String(localized: "passed") : String(localized: "sang")
        default: isUpNext ? String(localized: "up next") : nil
        }
        return [String(localized: "\(entry.displayName) to sing \(song)"), number.map { String(localized: "number \($0)") },
                state, (request?.mine ?? false) ? String(localized: "you") : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A break among the singers: nobody's called while it's on.
struct BreakRow: View {
    let entry: LineupEntry
    let isUpNext: Bool
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        let on = entry.state == .on
        HStack(spacing: DesignTokens.Spacing.s3) {
            Image(systemName: "cup.and.saucer").font(TokenFont.subheading)
                .foregroundStyle(Color(on ? colors.success : colors.inkMuted))
                .frame(width: DesignTokens.Size.avatarMd, height: DesignTokens.Size.avatarMd)
                .background(Color(on ? colors.successSoft : colors.surfaceSunken), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(TokenFont.subheading).foregroundStyle(Color(colors.ink))
                Text(String(localized: "Intermission")).font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
            }
            Spacer(minLength: DesignTokens.Spacing.s2)
            if on { Pill(text: String(localized: "On now"), symbol: nil, ink: colors.success, fill: colors.successSoft) }
            else if isUpNext { UpNextBadge() }
        }
        .padding(.horizontal, DesignTokens.Spacing.s4).padding(.vertical, DesignTokens.Spacing.s3)
        .frame(minHeight: 56)
        .background(Color(on ? colors.successSoft : .init(red: 0, green: 0, blue: 0, alpha: 0)))
        .accessibilityElement(children: .combine)
    }
}

/// The signed-in user's signup and where it stands: on the list (how many before them), up next (or up after the
/// break), on, or finished; Remove while it waits.
public struct MySignupCard: View {
    private let request: SongRequest
    private let entry: LineupEntry?
    private let number: Int?
    private let singersBefore: Int?
    private let isUpNext: Bool
    private let breakOnNow: LineupEntry?
    private let hostName: String?
    private let viewerName: String?
    private let onRemove: (@MainActor (SongRequest) async throws -> Void)?
    private let onDismiss: (() -> Void)?

    @State private var confirming = false
    @State private var removing = false
    @State private var failure: String?
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(request: SongRequest, entry: LineupEntry?, number: Int?, singersBefore: Int?, isUpNext: Bool,
                breakOnNow: LineupEntry? = nil, hostName: String? = nil, viewerName: String? = nil,
                onRemove: (@MainActor (SongRequest) async throws -> Void)?, onDismiss: (() -> Void)? = nil) {
        self.request = request
        self.entry = entry
        self.number = number
        self.singersBefore = singersBefore
        self.isUpNext = isUpNext
        self.breakOnNow = breakOnNow
        self.hostName = hostName
        self.viewerName = viewerName
        self.onRemove = onRemove
        self.onDismiss = onDismiss
    }

    private var onStage: Bool { request.state == .up || entry?.state == .on }

    private var headline: String {
        switch request.state {
        case .done: return String(localized: "You sang it")
        case .skipped: return String(localized: "The host passed on this one")
        case .withdrawn: return String(localized: "You're off the list")
        default:
            if onStage { return String(localized: "You're on") }
            if isUpNext { return breakOnNow == nil ? String(localized: "You're up next") : String(localized: "You're up after the break") }
            return String(localized: "You're on the list")
        }
    }

    private var detail: String {
        let host = hostName ?? String(localized: "the host")
        switch request.state {
        case .done: return String(localized: "Thanks for singing.")
        case .skipped: return String(localized: "You can sign up again any time.")
        case .withdrawn: return String(localized: "Sign up again whenever you like.")
        default:
            if onStage { return String(localized: "Go sing it.") }
            if isUpNext {
                if let breakOnNow { return String(localized: "\(breakOnNow.displayName) is on. Stay close; \(host) calls you when it ends.") }
                return String(localized: "Head for the stage when \(host) calls you")
            }
            let place = number.map { String(localized: " — number \($0) tonight") } ?? ""
            switch singersBefore ?? 0 {
            case 0: return String(localized: "Nobody before you\(place)")
            case 1: return String(localized: "1 singer before you\(place)")
            case let count: return String(localized: "\(count) singers before you\(place)")
            }
        }
    }

    private var songLine: String {
        guard let singer = request.singer, !singer.isEmpty, singer != viewerName else { return request.songLine }
        return "\(request.songLine) · " + String(localized: "as \(singer)")
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s3) {
            Image(systemName: "music.mic").font(TokenFont.subheading)
                .foregroundStyle(Color(onStage ? colors.success : request.state.isOpen ? colors.accentInk : colors.inkMuted))
                .frame(width: DesignTokens.Size.avatarMd, height: DesignTokens.Size.avatarMd)
                .background(Color(onStage ? colors.successSoft : request.state.isOpen ? colors.accentSoft : colors.controlFill),
                            in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(TokenFont.subheading).foregroundStyle(Color(colors.ink))
                Text(songLine).font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
                Text(detail).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            }
            Spacer(minLength: 0)
            if onRemove != nil && !onStage {
                Button { confirming = true } label: {
                    if removing { ProgressView() } else { Text(String(localized: "Remove")) }
                }
                .font(TokenFont.label).foregroundStyle(Color(colors.accentInk)).frame(minHeight: 44).disabled(removing)
            } else if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .foregroundStyle(Color(colors.inkMuted)).accessibilityLabel(String(localized: "Dismiss"))
            }
        }
        .buttonStyle(.plain)
        .padding(DesignTokens.Spacing.s4)
        .background(Color(onStage ? colors.successSoft : colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(onStage ? colors.success : request.state.isOpen ? colors.accent : colors.border))
        }
        .accessibilityElement(children: .combine)
        .alert(String(localized: "Remove yourself from the list?"), isPresented: $confirming) {
            Button(String(localized: "Remove"), role: .destructive) { remove() }
            Button(String(localized: "Stay on"), role: .cancel) {}
        } message: {
            Text((isUpNext ? String(localized: "You're up next. ") : "")
                 + String(localized: "\(request.title) stays yours to sign up for again later."))
        }
        .alert(String(localized: "Couldn't remove you"), isPresented: Binding(get: { failure != nil },
                                                                                  set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    private func remove() {
        guard let onRemove else { return }
        removing = true
        Task { @MainActor in
            defer { removing = false }
            do { try await onRemove(request) } catch { failure = error.localizedDescription }
        }
    }
}

/// Sign up to sing: the primary button while signups are open; drawn disabled with the venue's reason while closed or
/// paused; nothing when the venue doesn't take signups.
public struct KaraokeSignupButton: View {
    private let window: KaraokeWindow
    private let label: String
    private let action: () -> Void
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(window: KaraokeWindow, label: String = String(localized: "Sign up to sing"), action: @escaping () -> Void) {
        self.window = window
        self.label = label
        self.action = action
    }

    private var reason: String {
        if let reason = window.closedReason, !reason.isEmpty { return reason }
        return window.paused ? String(localized: "Signups are paused") : String(localized: "Signups open when a host is on.")
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        if window.permitted {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s2) {
                Button(action: action) {
                    Label(label, systemImage: "music.mic").font(TokenFont.label)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Color(window.open ? colors.onAccent : colors.inkMuted))
                        .background(Color(window.open ? colors.accent : colors.controlFill),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).disabled(!window.open)
                .accessibilityValue(window.open ? "" : reason)
                if !window.open {
                    Label(window.paused ? reason + " " + String(localized: "The singers already on the list still sing.") : reason,
                          systemImage: window.paused ? "pause" : "clock")
                        .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// The signup form: the song, its artist, who's singing (the viewer, or a duet: "Ada & Bo") and a note for the host.
/// The server's refusal shows at the top, the fields kept.
public struct KaraokeSignupSheet: View {
    private let viewerName: String?
    private let venueName: String
    private let hostName: String?
    private let submit: @MainActor (KaraokeSignup) async throws -> Void

    @State private var title = ""
    @State private var artist = ""
    @State private var singer: String
    @State private var note = ""
    @State private var sending = false
    @State private var refusal: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(viewerName: String?, venueName: String, hostName: String?,
                submit: @escaping @MainActor (KaraokeSignup) async throws -> Void) {
        self.viewerName = viewerName
        self.venueName = venueName
        self.hostName = hostName
        self.submit = submit
        _singer = State(initialValue: viewerName ?? "")
    }

    private var canSubmit: Bool {
        !sending && !title.trimmed.isEmpty && (viewerName != nil || !singer.trimmed.isEmpty)
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {
                    if let refusal {
                        Label(refusal, systemImage: "exclamationmark.circle").font(TokenFont.body)
                            .foregroundStyle(Color(colors.danger)).padding(DesignTokens.Spacing.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(colors.dangerSoft), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text(hostName.map { String(localized: "Tonight at \(venueName). \($0) is taking signups.") }
                         ?? String(localized: "Tonight at \(venueName)."))
                        .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    field(String(localized: "Song"), text: $title, prompt: String(localized: "Song title"), limit: 120)
                    field(String(localized: "Artist"), text: $artist, prompt: String(localized: "Who it's by (optional)"), limit: 120)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1 + 2) {
                        field(String(localized: "Singing as"), text: $singer, prompt: String(localized: "Your name"), limit: 120)
                        Text(String(localized: "How the host calls you up. Singing with someone? Add them: Ada & Bo"))
                            .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    }
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1 + 2) {
                        field(String(localized: "Note for the host"), text: $note,
                              prompt: String(localized: "A dedication, or a heads-up (optional)"), limit: 280, lines: 3)
                        if note.count > 200 {
                            Text("\(note.count)/280").font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                        }
                    }
                    Button(action: send) {
                        Group {
                            if sending { ProgressView() }
                            else { Label(String(localized: "Put me on the list"), systemImage: "music.mic") }
                        }
                        .font(TokenFont.label).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Color(canSubmit ? colors.onAccent : colors.inkMuted))
                        .background(Color(canSubmit ? colors.accent : colors.controlFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain).disabled(!canSubmit)
                }
                .padding(DesignTokens.Spacing.s4)
                .disabled(sending)
            }
            .background(Color(colors.surface))
            .navigationTitle(String(localized: "Sign up to sing"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }.disabled(sending)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(sending)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, limit: Int, lines: Int = 1) -> some View {
        let colors = preset.colors(scheme)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1 + 2) {
            Text(label).font(TokenFont.label).foregroundStyle(Color(colors.ink))
            TextField(prompt, text: text, axis: lines > 1 ? .vertical : .horizontal)
                .lineLimit(lines...max(lines, lines * 2))
                .font(TokenFont.body)
                .padding(.horizontal, DesignTokens.Spacing.s3).padding(.vertical, DesignTokens.Spacing.s2 + 2)
                .frame(minHeight: 44)
                .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(colors.borderStrong)) }
                .onChange(of: text.wrappedValue) { value in
                    if value.count > limit { text.wrappedValue = String(value.prefix(limit)) }
                }
                .accessibilityLabel(label)
        }
    }

    private func send() {
        let signup = KaraokeSignup(title: title.trimmed, artist: artist.trimmed.nilIfEmpty,
                                   singer: singer.trimmed == (viewerName ?? "") ? nil : singer.trimmed.nilIfEmpty,
                                   note: note.trimmed.nilIfEmpty)
        sending = true
        refusal = nil
        Task { @MainActor in
            defer { sending = false }
            do {
                try await submit(signup)
                dismiss()
            } catch {
                let message = error.localizedDescription
                refusal = message.isEmpty ? String(localized: "Couldn't sign you up. Check your connection and try again.") : message
            }
        }
    }
}

/// A partner's karaoke (KaraFun, a custom link): Join and the session's QR code, as an event's karaoke shows them.
struct KaraokeJoinSection: View {
    let session: VenueKaraoke
    let title: String?
    @State private var showingCode = false
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    private var joinTitle: String {
        session.providerName.map { String(localized: "Join \($0) session") } ?? String(localized: "Join karaoke session")
    }

    var body: some View {
        let colors = preset.colors(scheme)
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            HStack(alignment: .firstTextBaseline) {
                if let title { Text(title).font(TokenFont.heading).foregroundStyle(Color(colors.ink)).accessibilityAddTraits(.isHeader) }
                Spacer()
                if let name = session.providerName {
                    Text(String(localized: "with \(name)")).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if let url = session.joinURL {
                    Link(destination: url) { Label(joinTitle, systemImage: "music.mic").frame(maxWidth: .infinity, minHeight: 52, alignment: .leading) }
                        .padding(.horizontal, DesignTokens.Spacing.s4)
                    Divider().overlay(Color(colors.border))
                    Button { showingCode = true } label: {
                        Label(String(localized: "Show join code"), systemImage: "qrcode")
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    }
                    .buttonStyle(.plain).padding(.horizontal, DesignTokens.Spacing.s4)
                } else {
                    Label(String(localized: "Ask the host how to join the karaoke session."), systemImage: "music.mic")
                        .foregroundStyle(Color(colors.inkMuted)).padding(DesignTokens.Spacing.s4)
                }
            }
            .font(TokenFont.label).foregroundStyle(Color(colors.accentInk))
            .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(colors.border)) }
        }
        .padding(.horizontal, DesignTokens.Spacing.s4)
        .sheet(isPresented: $showingCode) {
            if let url = session.joinURL { KaraokeJoinCodeSheet(url: url, title: joinTitle, sessionCode: session.sessionCode) }
        }
    }
}

/// The partner session's QR code, large, so people nearby can scan straight in.
struct KaraokeJoinCodeSheet: View {
    let url: URL
    let title: String
    let sessionCode: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.s5) {
                Group {
                    if let image = QRCode.image(for: url.absoluteString) {
                        Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 280, maxHeight: 280)
                .padding(DesignTokens.Spacing.s4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(String(localized: "Karaoke join QR code"))
                if let sessionCode {
                    Text(sessionCode).font(.system(.largeTitle, design: .monospaced).weight(.semibold)).textSelection(.enabled)
                }
                Text(String(localized: "Scan to join")).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A QR code for a string, drawn by Core Image.
enum QRCode {
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
