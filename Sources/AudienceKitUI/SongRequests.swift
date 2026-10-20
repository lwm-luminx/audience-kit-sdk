#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

/// A venue's song requests tonight, next to ``KaraokeQueue``: what's playing now, Request a song (greyed with the
/// venue's reason while closed or paused), and the signed-in user's requests with where each stands and Withdraw
/// while it waits. Nothing when the venue doesn't take requests and the user has none waiting. Nothing fetches here:
/// pass the lineup and run the calls in the closures, then refetch.
public struct SongRequestsSection: View {
    private let lineup: VenueLineup
    private let signedIn: Bool
    private let title: String?
    private let onRequest: @MainActor (SongRequestDraft) async throws -> Void
    private let onWithdraw: @MainActor (SongRequest) async throws -> Void
    private let onSignInNeeded: (() -> Void)?

    @State private var requesting = false
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    /// - Parameters:
    ///   - lineup: the venue's lineup, from ``AudienceSession/lineup(venueID:)``; its ``VenueLineup/songRequests``.
    ///   - signedIn: whether someone is signed in; while not, Request a song calls `onSignInNeeded` when set.
    ///   - onRequest: asks for a song (``AudienceSession/requestSong(venueID:title:artist:note:)``); a thrown error
    ///     shows in the sheet.
    ///   - onWithdraw: takes a request back (``AudienceSession/withdrawSongRequest(id:)``).
    public init(lineup: VenueLineup, signedIn: Bool = true, title: String? = String(localized: "Song requests"),
                onRequest: @escaping @MainActor (SongRequestDraft) async throws -> Void,
                onWithdraw: @escaping @MainActor (SongRequest) async throws -> Void,
                onSignInNeeded: (() -> Void)? = nil) {
        self.lineup = lineup
        self.signedIn = signedIn
        self.title = title
        self.onRequest = onRequest
        self.onWithdraw = onWithdraw
        self.onSignInNeeded = onSignInNeeded
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var window: SongRequestWindow? { lineup.songRequests }
    private var mine: [SongRequest] { lineup.mySongRequests }

    public var body: some View {
        if let window, window.permitted || mine.contains(where: \.state.isOpen) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                heading(window)
                if let playing = window.playing { NowPlayingRow(request: playing) }
                if window.permitted {
                    SongRequestButton(window: window, label: mine.isEmpty ? String(localized: "Request a song")
                                                                          : String(localized: "Request another")) {
                        if !signedIn, let onSignInNeeded { onSignInNeeded() } else { requesting = true }
                    }
                }
                if !mine.isEmpty { yours(window) }
            }
            .padding(.horizontal, DesignTokens.Spacing.s4)
            .sheet(isPresented: $requesting) {
                SongRequestSheet(venueName: lineup.venueName, hostName: window.host?.displayName, submit: onRequest)
            }
        }
    }

    private func heading(_ window: SongRequestWindow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let title { Text(title).font(TokenFont.heading).foregroundStyle(Color(colors.ink)).accessibilityAddTraits(.isHeader) }
            Spacer()
            let waiting = window.queue.filter { $0.state == .queued }.count
            if waiting > 0 {
                Text(waiting == 1 ? String(localized: "1 in the queue") : String(localized: "\(waiting) in the queue"))
                    .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            }
        }
    }

    /// The user's requests tonight, newest first.
    private func yours(_ window: SongRequestWindow) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s2) {
            Text(String(localized: "Your requests")).font(TokenFont.label).foregroundStyle(Color(colors.inkMuted))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(mine.enumerated()), id: \.element.id) { index, request in
                    MySongRequestRow(request: request, requestsBefore: window.requestsBefore(request),
                                     onWithdraw: request.state == .queued ? onWithdraw : nil)
                    if index < mine.count - 1 { Divider().overlay(Color(colors.border)) }
                }
            }
            .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(colors.border)) }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension SongRequest.State {
    /// Where a song request stands, in words for the room: "In the queue", "Playing now", "Played", "Skipped",
    /// "Withdrawn".
    public var songStatus: String {
        switch self {
        case .queued: String(localized: "In the queue")
        case .up: String(localized: "Playing now")
        case .done: String(localized: "Played")
        case .skipped: String(localized: "Skipped")
        case .withdrawn: String(localized: "Withdrawn")
        case .unknown: String(localized: "Requested")
        }
    }
}

/// The song the host is playing from the requests: its title and artist, Now playing, and who asked.
struct NowPlayingRow: View {
    let request: SongRequest
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        HStack(spacing: DesignTokens.Spacing.s3) {
            Image(systemName: "music.note").font(TokenFont.subheading).foregroundStyle(Color(colors.success))
                .frame(width: DesignTokens.Size.avatarMd, height: DesignTokens.Size.avatarMd)
                .background(Color(colors.successSoft), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(request.songLine).font(TokenFont.subheading).lineLimit(1).foregroundStyle(Color(colors.ink))
                if let name = request.requesterName, !name.isEmpty {
                    Text(request.mine ? String(localized: "Your request") : String(localized: "For \(name)"))
                        .font(TokenFont.body).lineLimit(1).foregroundStyle(Color(colors.inkMuted))
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s2)
            Pill(text: String(localized: "Now playing"), symbol: "speaker.wave.2", ink: colors.success, fill: colors.successSoft)
        }
        .padding(.horizontal, DesignTokens.Spacing.s4).padding(.vertical, DesignTokens.Spacing.s3)
        .frame(minHeight: 56)
        .background(Color(colors.successSoft), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(colors.success)) }
        .accessibilityElement(children: .combine)
    }
}

/// One of the signed-in user's song requests: the song, where it stands (how many before it while it waits) and
/// Withdraw while it waits.
public struct MySongRequestRow: View {
    private let request: SongRequest
    private let requestsBefore: Int?
    private let onWithdraw: (@MainActor (SongRequest) async throws -> Void)?

    @State private var confirming = false
    @State private var withdrawing = false
    @State private var failure: String?
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(request: SongRequest, requestsBefore: Int? = nil,
                onWithdraw: (@MainActor (SongRequest) async throws -> Void)?) {
        self.request = request
        self.requestsBefore = requestsBefore
        self.onWithdraw = onWithdraw
    }

    private var playing: Bool { request.state == .up }

    /// "In the queue · 2 before you", "Playing now", "Played".
    private var status: String {
        guard request.state == .queued, let requestsBefore else { return request.state.songStatus }
        let place = switch requestsBefore {
        case 0: String(localized: "next up")
        case 1: String(localized: "1 before you")
        case let count: String(localized: "\(count) before you")
        }
        return "\(request.state.songStatus) · \(place)"
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        let open = request.state.isOpen
        HStack(spacing: DesignTokens.Spacing.s3) {
            Image(systemName: playing ? "speaker.wave.2" : "music.note").font(TokenFont.subheading)
                .foregroundStyle(Color(playing ? colors.success : open ? colors.accentInk : colors.inkMuted))
                .frame(width: DesignTokens.Size.avatarMd, height: DesignTokens.Size.avatarMd)
                .background(Color(playing ? colors.successSoft : open ? colors.accentSoft : colors.controlFill), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(request.songLine).font(TokenFont.subheading).lineLimit(1)
                    .foregroundStyle(Color(open ? colors.ink : colors.inkMuted))
                Text(status).font(TokenFont.bodySm).lineLimit(1)
                    .foregroundStyle(Color(playing ? colors.success : colors.inkMuted))
                if let note = request.note, !note.isEmpty {
                    Text(note).font(TokenFont.bodySm).lineLimit(2).foregroundStyle(Color(colors.inkMuted))
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s2)
            if onWithdraw != nil {
                Button { confirming = true } label: {
                    if withdrawing { ProgressView() } else { Text(String(localized: "Withdraw")) }
                }
                .buttonStyle(.plain)
                .font(TokenFont.label).foregroundStyle(Color(colors.accentInk)).frame(minHeight: 44).disabled(withdrawing)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s4).padding(.vertical, DesignTokens.Spacing.s3)
        .frame(minHeight: 56)
        .background(Color(playing ? colors.successSoft : .init(red: 0, green: 0, blue: 0, alpha: 0)))
        .accessibilityElement(children: .combine)
        .alert(String(localized: "Withdraw your request?"), isPresented: $confirming) {
            Button(String(localized: "Withdraw"), role: .destructive) { withdraw() }
            Button(String(localized: "Keep it"), role: .cancel) {}
        } message: {
            Text(String(localized: "\(request.title) comes off the queue. You can ask for it again later."))
        }
        .alert(String(localized: "Couldn't withdraw it"), isPresented: Binding(get: { failure != nil },
                                                                                 set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    private func withdraw() {
        guard let onWithdraw else { return }
        withdrawing = true
        Task { @MainActor in
            defer { withdrawing = false }
            do { try await onWithdraw(request) } catch { failure = error.localizedDescription }
        }
    }
}

/// Request a song: the primary button while requests are open; drawn disabled with the venue's reason while closed
/// or paused; nothing when the venue doesn't take requests.
public struct SongRequestButton: View {
    private let window: SongRequestWindow
    private let label: String
    private let action: () -> Void
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(window: SongRequestWindow, label: String = String(localized: "Request a song"),
                action: @escaping () -> Void) {
        self.window = window
        self.label = label
        self.action = action
    }

    private var reason: String {
        if let reason = window.closedReason, !reason.isEmpty { return reason }
        return window.paused ? String(localized: "Requests are paused") : String(localized: "Requests open when a host or DJ is on.")
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        if window.permitted {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s2) {
                Button(action: action) {
                    Label(label, systemImage: "music.note.list").font(TokenFont.label)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Color(window.open ? colors.onAccent : colors.inkMuted))
                        .background(Color(window.open ? colors.accent : colors.controlFill),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).disabled(!window.open)
                .accessibilityValue(window.open ? "" : reason)
                if !window.open {
                    Label(window.paused ? reason + " " + String(localized: "The songs already asked for still play.") : reason,
                          systemImage: window.paused ? "pause" : "clock")
                        .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// The request form: the song, its artist and an optional dedication or word for the host. The server's refusal
/// shows at the top, the fields kept.
public struct SongRequestSheet: View {
    private let venueName: String
    private let hostName: String?
    private let submit: @MainActor (SongRequestDraft) async throws -> Void

    @State private var title = ""
    @State private var artist = ""
    @State private var note = ""
    @State private var sending = false
    @State private var refusal: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(venueName: String, hostName: String?, submit: @escaping @MainActor (SongRequestDraft) async throws -> Void) {
        self.venueName = venueName
        self.hostName = hostName
        self.submit = submit
    }

    private var canSubmit: Bool { !sending && !title.trimmed.isEmpty }

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
                    Text(hostName.map { String(localized: "Tonight at \(venueName). \($0) is taking requests.") }
                         ?? String(localized: "Tonight at \(venueName)."))
                        .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    RequestField(label: String(localized: "Song"), text: $title, prompt: String(localized: "Song title"), limit: 120)
                    RequestField(label: String(localized: "Artist"), text: $artist,
                                 prompt: String(localized: "Who it's by (optional)"), limit: 120)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1 + 2) {
                        RequestField(label: String(localized: "Dedication or note"), text: $note,
                                     prompt: String(localized: "For the birthday girl, or a word for the host (optional)"),
                                     limit: 280, lines: 3)
                        if note.count > 200 {
                            Text("\(note.count)/280").font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                        }
                    }
                    Button(action: send) {
                        Group {
                            if sending { ProgressView() }
                            else { Label(String(localized: "Send request"), systemImage: "music.note.list") }
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
            .navigationTitle(String(localized: "Request a song"))
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

    private func send() {
        let draft = SongRequestDraft(title: title.trimmed, artist: artist.trimmed.nilIfEmpty, note: note.trimmed.nilIfEmpty)
        sending = true
        refusal = nil
        Task { @MainActor in
            defer { sending = false }
            do {
                try await submit(draft)
                dismiss()
            } catch {
                let message = error.localizedDescription
                refusal = message.isEmpty ? String(localized: "Couldn't send your request. Check your connection and try again.") : message
            }
        }
    }
}

/// A labelled text field drawn with the design tokens, cut off at `limit` characters.
private struct RequestField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    let limit: Int
    var lines = 1
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = preset.colors(scheme)
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1 + 2) {
            Text(label).font(TokenFont.label).foregroundStyle(Color(colors.ink))
            TextField(prompt, text: $text, axis: lines > 1 ? .vertical : .horizontal)
                .lineLimit(lines...max(lines, lines * 2))
                .font(TokenFont.body)
                .padding(.horizontal, DesignTokens.Spacing.s3).padding(.vertical, DesignTokens.Spacing.s2 + 2)
                .frame(minHeight: 44)
                .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(colors.borderStrong)) }
                .onChange(of: text) { value in
                    if value.count > limit { text = String(value.prefix(limit)) }
                }
                .accessibilityLabel(label)
        }
    }
}
#endif
