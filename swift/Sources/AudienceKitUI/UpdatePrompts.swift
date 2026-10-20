#if canImport(SwiftUI)
import AudienceKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// The update prompts (design: TestFlightUpdates.md): the soft sheet, the blocking screen, the TestFlight-missing sheet
// and the inline banner, drawn with the audience's tokens. `.audienceUpdatePrompts()` presents them for an
// `AudienceUpdates`; an app with its own UI can draw these views itself from `AudienceUpdates.prompt`.

extension View {
    /// Shows the app's update prompts over this view: checks for an update when the app comes to the foreground (at
    /// most once per `AudienceUpdates.minimumInterval`), then presents the soft or TestFlight-missing sheet, or the
    /// blocking screen, which can't be dismissed. Apply it once, at the root of the app, inside `.audiencePreset(_:)`.
    ///
    /// - Parameter updates: the prompts to show; `AudienceUpdates.shared` (from `AudienceUpdates.configure`) when
    ///   `nil`. With neither, this does nothing.
    @MainActor
    public func audienceUpdatePrompts(_ updates: AudienceUpdates? = nil) -> some View {
        AudienceUpdatePromptsHost(content: self, updates: updates ?? AudienceUpdates.shared)
    }
}

/// Presents an ``AudienceUpdates``' prompts over `content`.
struct AudienceUpdatePromptsHost<Content: View>: View {
    let content: Content
    let updates: AudienceUpdates?

    var body: some View {
        if let updates {
            UpdatePromptsPresenter(content: content, updates: updates)
        } else {
            content
        }
    }
}

private struct UpdatePromptsPresenter<Content: View>: View {
    let content: Content
    @ObservedObject var updates: AudienceUpdates
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task { await updates.checkOnForeground() }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await updates.checkOnForeground() }
            }
            .sheet(item: sheetPrompt) { prompt in
                UpdateSheetContainer(prompt: prompt, updates: updates)
            }
            #if os(iOS) || os(tvOS) || os(visionOS)
            .fullScreenCover(item: blockingPrompt) { prompt in
                UpdateScreen(prompt: prompt, appName: updates.appName,
                             onUpdate: { Task { await updates.openUpdate() } },
                             onAppStore: { Task { await updates.openAppStore() } })
                    .interactiveDismissDisabled()
            }
            #else
            .sheet(item: blockingPrompt) { prompt in
                UpdateScreen(prompt: prompt, appName: updates.appName,
                             onUpdate: { Task { await updates.openUpdate() } },
                             onAppStore: { Task { await updates.openAppStore() } })
                    .frame(minWidth: 480, minHeight: 640)
                    .interactiveDismissDisabled()
            }
            #endif
    }

    /// The soft or TestFlight-missing prompt. Swiping it away is "Not now".
    private var sheetPrompt: Binding<UpdatePrompt?> {
        Binding(
            get: { updates.prompt.flatMap { $0.isBlocking ? nil : $0 } },
            set: { prompt in if prompt == nil, updates.prompt?.isBlocking == false { updates.dismiss() } }
        )
    }

    /// The blocking prompt, which only an update ends.
    private var blockingPrompt: Binding<UpdatePrompt?> {
        Binding(get: { updates.prompt.flatMap { $0.isBlocking ? $0 : nil } }, set: { _ in })
    }
}

/// A soft or TestFlight-missing ``UpdateSheet`` as a sheet: sized to its content on phones, the system's centred form
/// sheet on iPad.
struct UpdateSheetContainer: View {
    let prompt: UpdatePrompt
    let updates: AudienceUpdates
    @State private var height: CGFloat = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isDialog: Bool {
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    var body: some View {
        ScrollView {
            UpdateSheet(prompt: prompt, appName: updates.appName, layout: isDialog ? .dialog : .sheet,
                        onUpdate: { Task { await updates.openUpdate() } },
                        onAppStore: { Task { await updates.openAppStore() } },
                        onNotNow: { updates.dismiss() })
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { height = proxy.size.height }
                        .onChange(of: proxy.size.height) { height = $0 }
                })
        }
        .presentationDetents(height > 0 && !isDialog ? [.height(height)] : [.large])
        .presentationDragIndicator(isDialog ? .hidden : .visible)
    }
}

// MARK: - UpdateSheet

/// The soft prompt (a new build is out) or the TestFlight-missing prompt: an app tile, the overline and title, a
/// paragraph, "What's new" or a notice, then the buttons. Put it in a sheet (`.audienceUpdatePrompts()` does), or a
/// centred dialog on iPad with ``Layout/dialog``.
public struct UpdateSheet: View {
    /// How the buttons sit: stacked full width under a footnote on phones, right-aligned in a dialog.
    public enum Layout: Sendable {
        case sheet
        case dialog
    }

    private let prompt: UpdatePrompt
    private let appName: String
    private let layout: Layout
    private let onUpdate: () -> Void
    private let onAppStore: () -> Void
    private let onNotNow: () -> Void

    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    /// - Parameters:
    ///   - prompt: ``UpdatePrompt/soft(_:)`` or ``UpdatePrompt/noTestFlight(_:)`` (a blocking prompt draws as soft;
    ///     use ``UpdateScreen`` for it).
    ///   - appName: the app's name in the copy.
    ///   - onUpdate: "Update in TestFlight" / "Update on the App Store" (`AudienceUpdates.openUpdate()`).
    ///   - onAppStore: "Get it on the App Store" (`AudienceUpdates.openAppStore()`).
    ///   - onNotNow: "Not now" (`AudienceUpdates.dismiss()`).
    public init(prompt: UpdatePrompt, appName: String, layout: Layout = .sheet, onUpdate: @escaping () -> Void,
                onAppStore: @escaping () -> Void, onNotNow: @escaping () -> Void)
    {
        self.prompt = prompt
        self.appName = appName
        self.layout = layout
        self.onUpdate = onUpdate
        self.onAppStore = onAppStore
        self.onNotNow = onNotNow
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var offer: UpdateOffer { prompt.offer }
    private var missingTestFlight: Bool {
        if case .noTestFlight = prompt { return true }
        return false
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
            HStack(spacing: DesignTokens.Spacing.s3) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    Text(UpdateCopy.overline(prompt, appName: appName))
                        .font(TokenFont.caption).textCase(.uppercase)
                        .foregroundStyle(Color(missingTestFlight ? colors.warning : colors.accentInk))
                    Text(UpdateCopy.title(prompt, appName: appName))
                        .font(UpdateFont.title).foregroundStyle(Color(colors.ink))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .accessibilityElement(children: .combine)

            Text(UpdateCopy.body(prompt, appName: appName))
                .font(TokenFont.body).foregroundStyle(Color(colors.ink))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if !missingTestFlight, !offer.notes.isEmpty { whatsNew }
            if missingTestFlight { notice }

            buttons

            if layout == .sheet {
                Text(UpdateCopy.footnote(prompt))
                    .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, layout == .sheet ? DesignTokens.Spacing.s5 : DesignTokens.Spacing.s6)
        .padding(.top, DesignTokens.Spacing.s6)
        .padding(.bottom, DesignTokens.Spacing.s6)
        .frame(maxWidth: layout == .dialog ? 480 : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(Color(colors.surfaceRaised))
        .accessibilityAction(.escape, onNotNow)
    }

    private var tile: some View {
        let glyph = missingTestFlight ? "exclamationmark.circle"
            : offer.channel == .testFlight ? "arrow.up" : "arrow.down.to.line"
        return Image(systemName: glyph)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color(missingTestFlight ? colors.warning : colors.onAccent))
            .frame(width: DesignTokens.Size.avatarLg, height: DesignTokens.Size.avatarLg)
            .background(Color(missingTestFlight ? colors.warningSoft : colors.accent),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "What's new"))
                .font(TokenFont.caption).textCase(.uppercase).foregroundStyle(Color(colors.inkMuted))
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(offer.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s2) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(note).fixedSize(horizontal: false, vertical: true)
                }
                .font(TokenFont.body).foregroundStyle(Color(colors.ink))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s4).padding(.vertical, DesignTokens.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(colors.surfaceSunken), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var notice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Color(colors.info)).accessibilityHidden(true)
            Text(String(localized: "Sign in with the same account and your friends, tags and chats are all there."))
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.ink))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignTokens.Spacing.s3).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(colors.infoSoft), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    @ViewBuilder
    private var buttons: some View {
        let primaryTitle = UpdateCopy.primaryButton(prompt)
        let primaryAction = missingTestFlight ? onAppStore : onUpdate
        let primaryGlyph = missingTestFlight ? "arrow.down.to.line" : "arrow.up.forward.square"
        switch layout {
        case .sheet:
            VStack(spacing: DesignTokens.Spacing.s2) {
                Button(action: primaryAction) { Label(primaryTitle, systemImage: primaryGlyph) }
                    .buttonStyle(UpdateButtonStyle(kind: .primary, colors: colors))
                Button(String(localized: "Not now"), action: onNotNow)
                    .buttonStyle(UpdateButtonStyle(kind: .quiet, colors: colors))
            }
        case .dialog:
            HStack(spacing: DesignTokens.Spacing.s2) {
                Spacer(minLength: 0)
                Button(String(localized: "Not now"), action: onNotNow)
                    .buttonStyle(UpdateButtonStyle(kind: .secondary, colors: colors, fullWidth: false))
                Button(action: primaryAction) { Text(primaryTitle) }
                    .buttonStyle(UpdateButtonStyle(kind: .primary, colors: colors, fullWidth: false))
            }
        }
    }
}

// MARK: - UpdateScreen

/// The blocking prompt: a full screen with no close control, for a build older than the oldest that still works.
/// TestFlight installs get "Update in TestFlight" and "Get it on the App Store instead"; App Store installs get
/// "Update on the App Store".
public struct UpdateScreen: View {
    private let offer: UpdateOffer
    private let appName: String
    private let onUpdate: () -> Void
    private let onAppStore: () -> Void

    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    /// - Parameters:
    ///   - prompt: the prompt (its offer is what's shown).
    ///   - appName: the app's name in the copy.
    ///   - onUpdate: "Update in TestFlight" / "Update on the App Store" (`AudienceUpdates.openUpdate()`).
    ///   - onAppStore: "Get it on the App Store instead" (`AudienceUpdates.openAppStore()`), TestFlight only.
    public init(prompt: UpdatePrompt, appName: String, onUpdate: @escaping () -> Void,
                onAppStore: @escaping () -> Void)
    {
        offer = prompt.offer
        self.appName = appName
        self.onUpdate = onUpdate
        self.onAppStore = onAppStore
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var testFlight: Bool { offer.channel == .testFlight }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.s4) {
            // Centred while it fits; scrolls at the largest text sizes.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.s4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(Color(colors.accentInk))
                            .frame(width: 96, height: 96)
                            .background(Color(colors.surfaceRaised),
                                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            .accessibilityHidden(true)
                        Text(testFlight ? UpdateCopy.betaOverline(appName) : UpdateCopy.updateOverline(appName))
                            .font(TokenFont.caption).textCase(.uppercase).foregroundStyle(Color(colors.accentInk))
                        Text(UpdateCopy.blockingTitle(offer.channel, appName: appName))
                            .font(UpdateFont.display).foregroundStyle(Color(colors.ink))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilitySortPriority(3)
                        Text(UpdateCopy.blockingBody(offer.channel, appName: appName))
                            .font(TokenFont.body).foregroundStyle(Color(colors.ink))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilitySortPriority(2)
                        rows
                    }
                    .padding(.vertical, DesignTokens.Spacing.s6)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
            VStack(spacing: DesignTokens.Spacing.s2) {
                Button(action: onUpdate) {
                    Label(testFlight ? String(localized: "Update in TestFlight")
                                     : String(localized: "Update on the App Store"),
                          systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(UpdateButtonStyle(kind: .primary, colors: colors))
                if testFlight, !offer.appStoreLinks.isEmpty {
                    Button(String(localized: "Get it on the App Store instead"), action: onAppStore)
                        .buttonStyle(UpdateButtonStyle(kind: .quiet, colors: colors))
                }
                Text(testFlight ? String(localized: "Your account, friends and chats come with you either way.")
                                : String(localized: "Your account, friends and chats come with you."))
                    .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s6)
        .padding(.bottom, DesignTokens.Spacing.s4)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(colors.surface).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// "You have" (Too old), "Oldest that still works" (TestFlight) and "Latest".
    private var rows: some View {
        VStack(spacing: 0) {
            row(String(localized: "You have"), value: offer.currentLabel, tooOld: true)
            if testFlight, let minimum = offer.minimumLabel {
                Divider().overlay(Color(colors.border))
                row(String(localized: "Oldest that still works"), value: minimum)
            }
            if let latest = offer.latestLabel {
                Divider().overlay(Color(colors.border))
                row(String(localized: "Latest"), value: latest)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s4).padding(.vertical, DesignTokens.Spacing.s1)
        .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    private func row(_ title: String, value: String, tooOld: Bool = false) -> some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Text(title).font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
            Spacer(minLength: DesignTokens.Spacing.s2)
            Text(value).font(TokenFont.label).monospacedDigit().foregroundStyle(Color(colors.ink))
            if tooOld {
                Text(String(localized: "Too old"))
                    .font(TokenFont.caption).foregroundStyle(Color(colors.warning))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(colors.warningSoft), in: Capsule())
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - UpdateBanner

/// The inline form of the soft prompt, for apps that use the custom-UI hook: "A new beta is ready" over
/// "Build 420215 · in TestFlight" (or "An update is ready" over "Version 2.2 · on the App Store"), Update, and a
/// close button that is "Not now".
public struct UpdateBanner: View {
    private let offer: UpdateOffer
    private let onUpdate: () -> Void
    private let onHide: () -> Void

    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(offer: UpdateOffer, onUpdate: @escaping () -> Void, onHide: @escaping () -> Void) {
        self.offer = offer
        self.onUpdate = onUpdate
        self.onHide = onHide
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }
    private var testFlight: Bool { offer.channel == .testFlight }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.s3) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(colors.onAccent))
                .frame(width: 36, height: 36)
                .background(Color(colors.accent), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(testFlight ? String(localized: "A new beta is ready") : String(localized: "An update is ready"))
                    .font(TokenFont.subheading).fontWeight(.bold).foregroundStyle(Color(colors.ink))
                Text(UpdateCopy.bannerDetail(offer))
                    .font(TokenFont.bodySm).monospacedDigit().foregroundStyle(Color(colors.inkMuted))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DesignTokens.Spacing.s2)
            Button(String(localized: "Update"), action: onUpdate)
                .buttonStyle(UpdateButtonStyle(kind: .primary, colors: colors, large: false, fullWidth: false))
            Button(action: onHide) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(colors.inkMuted))
            .accessibilityLabel(String(localized: "Hide until the next build"))
        }
        .padding(DesignTokens.Spacing.s3)
        .background(Color(colors.accentSoft), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .contain)
        .onAppear { UpdateAccessibility.announce(UpdateCopy.bannerAnnouncement(offer)) }
    }
}

extension UpdateBanner {
    /// The banner for `updates`' waiting update, Update opening it and close dismissing it; nothing when there's
    /// none or it was dismissed.
    @MainActor
    public static func `for`(_ updates: AudienceUpdates) -> some View {
        AudienceUpdateBanner(updates: updates)
    }
}

/// ``UpdateBanner`` for an ``AudienceUpdates``' pending update.
public struct AudienceUpdateBanner: View {
    @ObservedObject private var updates: AudienceUpdates

    public init(updates: AudienceUpdates) {
        self.updates = updates
    }

    public var body: some View {
        if let offer = updates.pendingUpdate {
            UpdateBanner(offer: offer, onUpdate: { Task { await updates.openUpdate() } },
                         onHide: { updates.dismiss() })
        }
    }
}

// MARK: - Copy

/// The prompts' words, from the design's copy.
@MainActor
enum UpdateCopy {
    static func betaOverline(_ appName: String) -> String { String(localized: "\(appName) beta") }
    static func updateOverline(_ appName: String) -> String { String(localized: "\(appName) update") }

    static func overline(_ prompt: UpdatePrompt, appName: String) -> String {
        switch prompt {
        case .noTestFlight: String(localized: "Beta updates are off")
        default: prompt.offer.channel == .testFlight ? betaOverline(appName) : updateOverline(appName)
        }
    }

    static func title(_ prompt: UpdatePrompt, appName: String) -> String {
        switch prompt {
        case .noTestFlight: String(localized: "You're not getting updates")
        case .blocking: blockingTitle(prompt.offer.channel, appName: appName)
        case .soft:
            prompt.offer.channel == .testFlight ? String(localized: "A new beta is ready")
                : String(localized: "An update is ready")
        }
    }

    static func body(_ prompt: UpdatePrompt, appName: String) -> String {
        let offer = prompt.offer
        switch prompt {
        case .noTestFlight:
            return String(localized: "This copy of \(appName) came from the beta, but the TestFlight app isn't on this \(device), so new builds can't reach you. Get \(appName) from the App Store to stay up to date.")
        case .blocking:
            return blockingBody(offer.channel, appName: appName)
        case .soft where offer.channel == .testFlight:
            let latest = offer.latestBuild.map { String($0) } ?? ""
            let current = String(offer.currentBuild)
            return String(localized: "Build \(latest) is out and you're on \(current). Updating takes about a minute in TestFlight, and your account and chats stay as they are.")
        case .soft:
            let latest = offer.latestVersion.flatMap { $0.isEmpty ? nil : $0 } ?? offer.latestLabel ?? ""
            return String(localized: "\(appName) \(latest) is on the App Store and you're on \(offer.currentVersion). Your account and chats stay as they are.")
        }
    }

    static func blockingTitle(_ channel: UpdateChannel, appName: String) -> String {
        channel == .testFlight ? String(localized: "Update to keep testing")
            : String(localized: "Update to keep using \(appName)")
    }

    static func blockingBody(_ channel: UpdateChannel, appName: String) -> String {
        channel == .testFlight
            ? String(localized: "This beta is too old to work with \(appName) anymore. Get the latest build in TestFlight and you'll be right back where you were.")
            : String(localized: "This version is too old to work with \(appName) anymore. Get the latest from the App Store and you'll be right back where you were.")
    }

    static func primaryButton(_ prompt: UpdatePrompt) -> String {
        if case .noTestFlight = prompt { return String(localized: "Get it on the App Store") }
        return prompt.offer.channel == .testFlight ? String(localized: "Update in TestFlight")
            : String(localized: "Update on the App Store")
    }

    static func footnote(_ prompt: UpdatePrompt) -> String {
        switch prompt {
        case .noTestFlight:
            String(localized: "Rather keep testing? Install TestFlight from the App Store, then open this beta from it.")
        default:
            prompt.offer.channel == .testFlight
                ? String(localized: "Not now skips this build. We'll tell you when the next one lands.")
                : String(localized: "Not now skips this version. We'll tell you when the next one is out.")
        }
    }

    /// "Build 420215 · in TestFlight", "Version 2.2 · on the App Store".
    static func bannerDetail(_ offer: UpdateOffer) -> String {
        let latest = offer.latestLabel ?? ""
        return offer.channel == .testFlight ? String(localized: "\(latest) · in TestFlight")
            : String(localized: "\(latest) · on the App Store")
    }

    static func bannerAnnouncement(_ offer: UpdateOffer) -> String {
        let title = offer.channel == .testFlight ? String(localized: "A new beta is ready")
            : String(localized: "An update is ready")
        return "\(title). \(bannerDetail(offer))"
    }

    /// "iPhone", "iPad" or "Mac", for "isn't on this iPhone".
    static var device: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #elseif os(macOS)
        return "Mac"
        #else
        return "device"
        #endif
    }
}

enum UpdateFont {
    static var title: Font { DesignTokens.Typography.title.font(relativeTo: .title) }
    static var display: Font { DesignTokens.Typography.display.font(relativeTo: .largeTitle) }
}

enum UpdateAccessibility {
    /// Announces the banner without moving focus to it, as a `status` region would.
    @MainActor
    static func announce(_ text: String) {
        #if canImport(UIKit) && !os(watchOS)
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }
}

/// The token buttons: `primary` (accent fill), `secondary` (control fill) and `quiet` (accent text), 44pt tall at
/// `lg`.
struct UpdateButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case quiet
    }

    let kind: Kind
    let colors: DesignTokens.Colors
    var large = true
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let foreground: RGBAColor = switch kind {
        case .primary: colors.onAccent
        case .secondary: colors.ink
        case .quiet: colors.accentInk
        }
        let fill: Color = switch kind {
        case .primary: Color(pressed ? colors.accentStrong : colors.accent)
        case .secondary: Color(pressed ? colors.controlFillHover : colors.controlFill)
        case .quiet: pressed ? Color(colors.pressOverlay) : .clear
        }
        return configuration.label
            .font(TokenFont.label)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, large ? DesignTokens.Spacing.s4 : DesignTokens.Spacing.s3)
            .padding(.vertical, large ? 10 : 6)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: large ? 44 : 32)
            .foregroundStyle(Color(foreground))
            .background(fill, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }
}

// MARK: - UIKit

#if canImport(UIKit) && os(iOS)
/// The update prompts for a UIKit app: checks when the app becomes active and presents the sheets and the blocking
/// screen over the view controller `presenter` returns (usually the window's root). Keep it for the app's lifetime.
@MainActor
public final class AudienceUpdatePromptPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private let updates: AudienceUpdates
    private let presenter: @MainActor () -> UIViewController?
    private let preset: String
    private var watcher: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private weak var presented: UIViewController?
    private var presentedID: String?

    /// - Parameters:
    ///   - updates: the prompts; `AudienceUpdates.shared` when `nil` (then `configure` it first).
    ///   - preset: the design preset to draw with ("default", "hot_mess").
    ///   - presenter: the view controller to present from.
    public init?(updates: AudienceUpdates? = nil, preset: String = "default",
                 presenter: @escaping @MainActor () -> UIViewController?)
    {
        guard let updates = updates ?? AudienceUpdates.shared else { return nil }
        self.updates = updates
        self.preset = preset
        self.presenter = presenter
        super.init()
    }

    /// Starts checking on foreground and presenting prompts.
    public func start() {
        guard watcher == nil else { return }
        let updates = updates
        watcher = Task { [weak self] in
            for await prompt in updates.prompts {
                self?.show(prompt)
            }
        }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in await updates.checkOnForeground() }
        }
        Task { await updates.checkOnForeground() }
    }

    /// Stops checking and presenting.
    public func stop() {
        watcher?.cancel()
        watcher = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func show(_ prompt: UpdatePrompt?) {
        guard prompt?.id != presentedID else { return }
        let next = { [weak self] in
            guard let self else { return }
            presentedID = nil
            guard let prompt, let host = presenter() else { return }
            present(prompt, from: host)
        }
        if let presented, presented.presentingViewController != nil {
            presented.dismiss(animated: true, completion: next)
        } else {
            next()
        }
    }

    private func present(_ prompt: UpdatePrompt, from host: UIViewController) {
        var top = host
        while let next = top.presentedViewController { top = next }

        let updates = updates
        let controller: UIViewController
        if prompt.isBlocking {
            controller = UIHostingController(rootView: UpdateScreen(
                prompt: prompt, appName: updates.appName,
                onUpdate: { Task { await updates.openUpdate() } },
                onAppStore: { Task { await updates.openAppStore() } }
            ).audiencePreset(preset))
            controller.modalPresentationStyle = .fullScreen
            controller.isModalInPresentation = true
        } else {
            controller = UIHostingController(rootView: UpdateSheet(
                prompt: prompt, appName: updates.appName,
                layout: top.traitCollection.horizontalSizeClass == .regular ? .dialog : .sheet,
                onUpdate: { Task { await updates.openUpdate() } },
                onAppStore: { Task { await updates.openAppStore() } },
                onNotNow: { updates.dismiss() }
            ).audiencePreset(preset))
            controller.modalPresentationStyle = .formSheet
            if let sheet = controller.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            controller.presentationController?.delegate = self
        }
        presented = controller
        presentedID = prompt.id
        top.present(controller, animated: true)
    }

    /// Swiping the sheet away is "Not now".
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentedID = nil
        updates.dismiss()
    }
}
#endif
#endif
