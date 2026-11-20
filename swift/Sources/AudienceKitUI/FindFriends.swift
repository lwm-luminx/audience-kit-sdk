// tvOS: AudienceKitUI on Apple TV is only the shared look (Theme, DesignTokens, AudienceAvatar) for Velvet's TV app.
#if !os(tvOS)
#if canImport(SwiftUI) && canImport(Contacts)
import AudienceCore
import AudienceKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// The find-friends screens (the API's doc/design-system/ContactFriendMatching.md): a card that offers it, the flow
// that verifies a number and checks contacts, the matches, the requests, and the settings. All of them draw from one
// ContactMatchingModel. Copy rules: never "upload", "sync" or "hash"; a hash is a "scrambled code".

// MARK: - Pieces

/// What a text field holds, for the keyboard and autofill on iOS.
private enum FieldKind { case givenName, familyName, phone, code }

private extension View {
    @ViewBuilder
    func fieldKind(_ kind: FieldKind) -> some View {
        #if os(iOS)
        switch kind {
        case .givenName: textContentType(.givenName)
        case .familyName: textContentType(.familyName)
        case .phone: textContentType(.telephoneNumber).keyboardType(.phonePad)
        case .code: textContentType(.oneTimeCode).keyboardType(.numberPad)
        }
        #else
        self
        #endif
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let colors: DesignTokens.Colors
    var danger = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokenFont.label)
            .foregroundStyle(Color(danger ? colors.surfaceRaised : colors.onAccent))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, DesignTokens.Spacing.s4)
            .background(Color(danger ? colors.danger : colors.accent),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    let colors: DesignTokens.Colors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokenFont.label)
            .foregroundStyle(Color(colors.accentInk))
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct Disc: View {
    let systemImage: String
    let size: CGFloat
    let colors: DesignTokens.Colors

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color(colors.accentInk))
            .frame(width: size, height: size)
            .background(Color(colors.accentSoft), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct Promise: View {
    let systemImage: String
    let title: String
    let detail: String
    let colors: DesignTokens.Colors

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s3) {
            Disc(systemImage: systemImage, size: 36, colors: colors)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1) {
                Text(title).font(TokenFont.label).foregroundStyle(Color(colors.ink))
                Text(detail).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorLine: View {
    let message: String?
    let colors: DesignTokens.Colors

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.danger))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func card(_ colors: DesignTokens.Colors) -> some View {
        padding(DesignTokens.Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.photo))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.photo).strokeBorder(Color(colors.border)) }
    }
}

// MARK: - The card on Now

/// "Find friends from your contacts", for the top of a home screen while the person hasn't turned matching on. Draws
/// nothing when ``ContactMatchingModel/offersCard`` is false. "Not now" hides it for 30 days.
public struct FindFriendsCard: View {
    @ObservedObject private var model: ContactMatchingModel
    private let onFind: @MainActor () -> Void
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(model: ContactMatchingModel, onFind: @escaping @MainActor () -> Void) {
        self.model = model
        self.onFind = onFind
    }

    public var body: some View {
        if model.offersCard {
            let colors = preset.colors(scheme)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.s3) {
                    Disc(systemImage: "person.badge.plus", size: 44, colors: colors)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1) {
                        Text(ContactMatchingCopy.title).font(TokenFont.heading).foregroundStyle(Color(colors.ink))
                            .accessibilityAddTraits(.isHeader)
                        Text(ContactMatchingCopy.cardBody).font(TokenFont.bodySm)
                            .foregroundStyle(Color(colors.inkMuted)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: DesignTokens.Spacing.s2) {
                    Button(ContactMatchingCopy.findFriends) { onFind() }
                        .buttonStyle(PrimaryButtonStyle(colors: colors))
                    Button(ContactMatchingCopy.notNow) { withAnimation { model.hideCard() } }
                        .buttonStyle(QuietButtonStyle(colors: colors))
                }
            }
            .card(colors)
        }
    }
}

// MARK: - Requests

/// The requests waiting on the person's answer, one card each: "Accept" and "Not now". Draws nothing without any.
public struct FriendRequestCards: View {
    @ObservedObject private var model: ContactMatchingModel
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(model: ContactMatchingModel) {
        self.model = model
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        ForEach(model.incomingRequests) { request in
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                HStack(spacing: DesignTokens.Spacing.s3) {
                    AudienceAvatar(url: model.client.url(for: request.user.avatarUrl), name: request.user.name, size: 56)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1) {
                        Text(request.user.name).font(TokenFont.heading).foregroundStyle(Color(colors.ink))
                        if let saved = model.savedName(for: request.user.id) {
                            Text(ContactMatchingCopy.savedAs(saved)).font(TokenFont.bodySm)
                                .foregroundStyle(Color(colors.inkMuted))
                        }
                        Text("Found through contacts").font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                    }
                }
                HStack(spacing: DesignTokens.Spacing.s2) {
                    Button("Accept") { Task { await model.respond(to: request, accept: true) } }
                        .buttonStyle(PrimaryButtonStyle(colors: colors))
                    Button(ContactMatchingCopy.notNow) { Task { await model.respond(to: request, accept: false) } }
                        .buttonStyle(QuietButtonStyle(colors: colors))
                }
                .disabled(model.working)
                Text(ContactMatchingCopy.notNowIsQuiet).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            }
            .card(colors)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(request.user.name) wants to be friends")
        }
    }
}

// MARK: - Matches

/// Everyone contact matching found, each with "Add", "Requested" or "Friends", and "Add N friends" under them. The
/// empty state when nobody was found. Used at the end of ``FindFriendsFlow`` and on its own from a push.
public struct ContactMatchesView: View {
    @ObservedObject private var model: ContactMatchingModel
    private let appName: String
    private let onDone: @MainActor () -> Void
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    public init(model: ContactMatchingModel, appName: String, onDone: @escaping @MainActor () -> Void) {
        self.model = model
        self.appName = appName
        self.onDone = onDone
    }

    private var matches: [ContactMatch] { model.state?.matches ?? [] }

    public var body: some View {
        let colors = preset.colors(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
                if matches.isEmpty { empty(colors) } else { found(colors) }
                ErrorLine(message: model.error, colors: colors)
            }
            .padding(DesignTokens.Spacing.s4)
        }
        .background(Color(colors.surface))
        .task { if model.state == nil { await model.load() } }
    }

    @ViewBuilder
    private func found(_ colors: DesignTokens.Colors) -> some View {
        Text(ContactMatchingCopy.friendsHere(matches.count)).font(TokenFont.title).foregroundStyle(Color(colors.ink))
            .accessibilityAddTraits(.isHeader)
        Text("You have each other's numbers saved. Add them and they'll get a request.")
            .font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
        VStack(spacing: 0) {
            ForEach(matches) { match in
                row(match, colors)
                if match.id != matches.last?.id { Divider() }
            }
        }
        .card(colors)
        if let batch = model.lastBatch {
            Text("We'll let you know when more friends turn this on. \(ContactMatchingCopy.checked(batch))")
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
        }
        let addable = model.state?.addable.count ?? 0
        if addable > 1 {
            Button(ContactMatchingCopy.addFriends(addable)) { Task { await model.addAll() } }
                .buttonStyle(PrimaryButtonStyle(colors: colors)).disabled(model.working)
        }
        Button("Done") { onDone() }.buttonStyle(QuietButtonStyle(colors: colors))
    }

    private func row(_ match: ContactMatch, _ colors: DesignTokens.Colors) -> some View {
        HStack(spacing: DesignTokens.Spacing.s3) {
            AudienceAvatar(url: model.client.url(for: match.user.avatarUrl), name: match.user.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.user.name).font(TokenFont.label).foregroundStyle(Color(colors.ink))
                if let saved = model.savedName(for: match.user.id) {
                    Text(ContactMatchingCopy.savedAs(saved)).font(TokenFont.bodySm)
                        .foregroundStyle(Color(colors.inkMuted))
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s2)
            switch match.status {
            case .none:
                Button("Add") { Task { await model.add(match) } }
                    .font(TokenFont.label).foregroundStyle(Color(colors.onAccent))
                    .padding(.horizontal, DesignTokens.Spacing.s3).frame(minHeight: 36)
                    .background(Color(colors.accent), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .buttonStyle(.plain).disabled(model.working)
                    .accessibilityLabel("Add \(match.user.name)")
            case .incoming:
                if let request = match.request {
                    Button("Accept") { Task { await model.respond(to: request, accept: true) } }
                        .font(TokenFont.label).foregroundStyle(Color(colors.onAccent))
                        .padding(.horizontal, DesignTokens.Spacing.s3).frame(minHeight: 36)
                        .background(Color(colors.accent), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                        .buttonStyle(.plain).disabled(model.working)
                        .accessibilityLabel("Accept \(match.user.name)")
                }
            case .requested:
                badge("Requested", ink: colors.accentInk, fill: colors.accentSoft)
            case .friends:
                badge("Friends", ink: colors.inkMuted, fill: colors.surfaceSunken)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.s2)
    }

    private func badge(_ text: String, ink: RGBAColor, fill: RGBAColor) -> some View {
        Text(text).font(TokenFont.caption).foregroundStyle(Color(ink))
            .padding(.horizontal, DesignTokens.Spacing.s2).padding(.vertical, DesignTokens.Spacing.s1)
            .background(Color(fill), in: Capsule())
    }

    @ViewBuilder
    private func empty(_ colors: DesignTokens.Colors) -> some View {
        VStack(spacing: DesignTokens.Spacing.s3) {
            Disc(systemImage: "person.2", size: 72, colors: colors)
            Text(ContactMatchingCopy.noFriendsYet).font(TokenFont.title).foregroundStyle(Color(colors.ink))
                .accessibilityAddTraits(.isHeader)
            Text(ContactMatchingCopy.noFriendsBody).font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
                .multilineTextAlignment(.center)
            if let batch = model.lastBatch {
                Text(ContactMatchingCopy.checked(batch)).font(TokenFont.bodySm)
                    .foregroundStyle(Color(colors.inkMuted)).multilineTextAlignment(.center)
            }
            Button("Done") { onDone() }.buttonStyle(PrimaryButtonStyle(colors: colors))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.s8)
    }
}

// MARK: - The flow

/// The whole opt-in, for a sheet: what happens, the name and number, the code from the text, the contacts prompt,
/// the check and the matches. Opens at the contacts step for someone whose number is already verified.
///
/// ```swift
/// .sheet(isPresented: $finding) {
///     FindFriendsFlow(model: friends, appName: "Hot Mess", firstName: me.firstName, lastName: me.lastName) {
///         finding = false
///     }
/// }
/// ```
public struct FindFriendsFlow: View {
    enum Step { case intro, number, code, contacts, checking, results }

    @ObservedObject private var model: ContactMatchingModel
    private let appName: String
    private let onDone: @MainActor () -> Void
    @State private var step: Step
    @State private var firstName: String
    @State private var lastName: String
    @State private var region: String
    @State private var number = ""
    @State private var code = ""
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    /// - Parameters:
    ///   - firstName, lastName: the profile's name, to start the match name from.
    public init(model: ContactMatchingModel, appName: String, firstName: String = "", lastName: String = "",
                onDone: @escaping @MainActor () -> Void)
    {
        self.model = model
        self.appName = appName
        self.onDone = onDone
        let state = model.state
        _step = State(initialValue: state?.phoneVerified == true ? .contacts : .intro)
        _firstName = State(initialValue: state?.firstName ?? firstName)
        _lastName = State(initialValue: state?.lastName ?? lastName)
        let phoneRegion = model.region?.uppercased() ?? "US"
        _region = State(initialValue: ContactHashing.callingCode(region: phoneRegion) == nil ? "US" : phoneRegion)
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        Group {
            if step == .results {
                ContactMatchesView(model: model, appName: appName, onDone: onDone)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
                        switch step {
                        case .intro: intro(colors)
                        case .number: numberStep(colors)
                        case .code: codeStep(colors)
                        case .contacts: contactsStep(colors)
                        case .checking, .results: checking(colors)
                        }
                    }
                    .padding(DesignTokens.Spacing.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(colors.surface))
            }
        }
        .onChange(of: step) { _ in model.error = nil }
    }

    // What happens

    @ViewBuilder
    private func intro(_ colors: DesignTokens.Colors) -> some View {
        Text(ContactMatchingCopy.title).font(TokenFont.title).foregroundStyle(Color(colors.ink))
            .accessibilityAddTraits(.isHeader)
        Text("Here's what happens if you turn this on.").font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
        Promise(systemImage: "lock.iphone", title: "Your contacts stay on your phone.",
                detail: "Each name and number becomes a scrambled code before it leaves. We keep only the codes, so "
                    + "we can tell you when a friend joins later, and delete them when you turn this off.",
                colors: colors)
        Promise(systemImage: "person.text.rectangle", title: "Only people you really know.",
                detail: "It's a match only when a first name, last name and number all line up. Nicknames count, so "
                    + "Danny finds Daniel. Contacts saved with just a first name are skipped.",
                colors: colors)
        Promise(systemImage: "arrow.left.arrow.right", title: "It works both ways.",
                detail: "You'll only see people who turned this on and have your number saved too. Nobody becomes a "
                    + "friend until you both say yes.",
                colors: colors)
        Button("Continue") { step = .number }.buttonStyle(PrimaryButtonStyle(colors: colors))
        Button(ContactMatchingCopy.notNow) { onDone() }.buttonStyle(QuietButtonStyle(colors: colors))
        Text("You can turn it off any time in Settings.").font(TokenFont.bodySm)
            .foregroundStyle(Color(colors.inkMuted)).frame(maxWidth: .infinity)
    }

    // Step 1: name and number

    @ViewBuilder
    private func numberStep(_ colors: DesignTokens.Colors) -> some View {
        stepLabel("Step 1 of 2", colors)
        Text("So friends can find you").font(TokenFont.title).foregroundStyle(Color(colors.ink))
            .accessibilityAddTraits(.isHeader)
        Text("Friends match you by the name and number they've saved for you. We'll text a code to make sure the "
            + "number is yours.")
            .font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            HStack(spacing: DesignTokens.Spacing.s2) {
                field("First name", text: $firstName, colors).fieldKind(.givenName)
                field("Last name", text: $lastName, colors).fieldKind(.familyName)
            }
            Text("Use the name your friends would save you under.").font(TokenFont.bodySm)
                .foregroundStyle(Color(colors.inkMuted))
            HStack(spacing: DesignTokens.Spacing.s2) {
                Picker("Country", selection: $region) {
                    ForEach(ContactHashing.regions, id: \.self) { region in
                        Text("\(region) +\(ContactHashing.callingCode(region: region) ?? "")").tag(region)
                    }
                }
                .pickerStyle(.menu).labelsHidden().tint(Color(colors.accentInk))
                field("Mobile number", text: $number, colors).fieldKind(.phone)
            }
        }
        .card(colors)
        Label(ContactMatchingCopy.numberPrivate, systemImage: "info.circle").font(TokenFont.bodySm)
            .foregroundStyle(Color(colors.inkMuted))
        ErrorLine(message: model.error, colors: colors)
        Button("Text me a code") {
            Task {
                if await model.start(number: number, region: region, firstName: firstName, lastName: lastName) {
                    code = ""
                    step = .code
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(colors: colors))
        .disabled(model.working || number.isEmpty || firstName.isEmpty || lastName.isEmpty)
        Text(ContactMatchingCopy.ratesMayApply).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            .frame(maxWidth: .infinity)
    }

    // Step 1: the code

    @ViewBuilder
    private func codeStep(_ colors: DesignTokens.Colors) -> some View {
        stepLabel("Step 1 of 2", colors)
        Text("Enter the code").font(TokenFont.title).foregroundStyle(Color(colors.ink))
            .accessibilityAddTraits(.isHeader)
        Text("We texted a 6-digit code to \(number).").font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
        TextField("6-digit code", text: $code)
            .font(.system(size: 28, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .fieldKind(.code)
            .padding(DesignTokens.Spacing.s3)
            .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(Color(colors.borderStrong))
            }
            .onChange(of: code) { value in
                let digits = String(value.filter(\.isNumber).prefix(6))
                if digits != value { code = digits }
            }
        ErrorLine(message: model.error, colors: colors)
        Button("Verify") {
            Task { if await model.verify(code: code) { step = .contacts } }
        }
        .buttonStyle(PrimaryButtonStyle(colors: colors)).disabled(model.working || code.count < 6)
        resend(colors)
        Button("Change number") { step = .number }.buttonStyle(QuietButtonStyle(colors: colors))
        Text("We fill the code in for you when the text arrives.").font(TokenFont.bodySm)
            .foregroundStyle(Color(colors.inkMuted)).frame(maxWidth: .infinity)
    }

    private func resend(_ colors: DesignTokens.Colors) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = Int((model.state?.codeResendAt ?? context.date).timeIntervalSince(context.date).rounded(.up))
            if wait > 0, wait <= 120 {
                Text("You can ask for a new code in \(wait / 60):\(String(format: "%02d", wait % 60)).")
                    .font(TokenFont.bodySm).monospacedDigit().foregroundStyle(Color(colors.inkMuted))
                    .frame(maxWidth: .infinity)
            } else if wait > 120 {
                Text("You've asked for a lot of codes. Try again tomorrow.").font(TokenFont.bodySm)
                    .foregroundStyle(Color(colors.inkMuted)).frame(maxWidth: .infinity)
            } else {
                Button("Send a new code") {
                    Task {
                        await model.start(number: number, region: region, firstName: firstName, lastName: lastName)
                    }
                }
                .buttonStyle(QuietButtonStyle(colors: colors)).disabled(model.working)
            }
        }
    }

    // Step 2: contacts

    @ViewBuilder
    private func contactsStep(_ colors: DesignTokens.Colors) -> some View {
        stepLabel("Step 2 of 2", colors)
        Label("Number verified", systemImage: "checkmark.seal.fill").font(TokenFont.caption)
            .foregroundStyle(Color(colors.success))
        Text("Now let us check your contacts").font(TokenFont.title).foregroundStyle(Color(colors.ink))
            .accessibilityAddTraits(.isHeader)
        Text("Next, your phone asks if \(appName) can see your contacts. Share all of them, or pick just the people "
            + "you'd like to find.")
            .font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            Text("What leaves your phone").font(TokenFont.label).foregroundStyle(Color(colors.ink))
            Label("A scrambled code for each first name, last name and number", systemImage: "checkmark")
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.success))
            Divider()
            Text("What never does").font(TokenFont.label).foregroundStyle(Color(colors.ink))
            ForEach(["Names, numbers, emails, photos, addresses or notes", "Contacts saved with only a first name",
                     "Anything that tells your contacts you checked"], id: \.self) { line in
                Label(line, systemImage: "xmark").font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
            }
        }
        .card(colors)
        if model.contactsDenied {
            Label("\(appName) can't see your contacts. Turn it on in Settings › \(appName) › Contacts.",
                  systemImage: "exclamationmark.triangle")
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.ink))
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(QuietButtonStyle(colors: colors))
            #endif
        }
        ErrorLine(message: model.error, colors: colors)
        Button("Continue") {
            Task {
                step = .checking
                step = await model.checkContacts() ? .results : .contacts
            }
        }
        .buttonStyle(PrimaryButtonStyle(colors: colors)).disabled(model.working)
        Button(ContactMatchingCopy.notNow) { onDone() }.buttonStyle(QuietButtonStyle(colors: colors))
    }

    @ViewBuilder
    private func checking(_ colors: DesignTokens.Colors) -> some View {
        VStack(spacing: DesignTokens.Spacing.s3) {
            Disc(systemImage: "person.crop.circle.badge.checkmark", size: 72, colors: colors)
            Text(ContactMatchingCopy.checking).font(TokenFont.title).foregroundStyle(Color(colors.ink))
                .accessibilityAddTraits(.isHeader)
            Text(ContactMatchingCopy.onlyCodesLeave).font(TokenFont.body).foregroundStyle(Color(colors.inkMuted))
            ProgressView().tint(Color(colors.accent))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.s12)
    }

    private func stepLabel(_ text: String, _ colors: DesignTokens.Colors) -> some View {
        Text(text).font(TokenFont.caption).foregroundStyle(Color(colors.inkMuted))
    }

    private func field(_ title: String, text: Binding<String>, _ colors: DesignTokens.Colors) -> some View {
        TextField(title, text: text)
            .font(TokenFont.body)
            .padding(DesignTokens.Spacing.s3)
            .background(Color(colors.surface), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.md).strokeBorder(Color(colors.border)) }
            .accessibilityLabel(title)
    }
}

// MARK: - Settings

/// The contact matching settings, for a settings screen: whether it's on, the number and the name friends match on,
/// the last check with "Check again", and "Turn off and delete my codes".
public struct ContactMatchingSettings: View {
    @ObservedObject private var model: ContactMatchingModel
    private let appName: String
    private let onFind: @MainActor () -> Void
    @State private var confirmingOff = false
    @State private var editingName = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var notice: String?
    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme

    /// - Parameter onFind: opens ``FindFriendsFlow``, for someone who hasn't turned matching on.
    public init(model: ContactMatchingModel, appName: String, onFind: @escaping @MainActor () -> Void) {
        self.model = model
        self.appName = appName
        self.onFind = onFind
    }

    public var body: some View {
        let colors = preset.colors(scheme)
        List {
            if let state = model.state, state.enabled {
                on(state, colors)
            } else {
                Section {
                    Button(ContactMatchingCopy.title) { onFind() }
                        .disabled(model.state?.textCodesAvailable == false)
                } footer: {
                    Text(model.state?.textCodesAvailable == false
                        ? "This isn't available yet. Check back soon."
                        : "People who turned this on and have your number saved can find you, and you can find them.")
                }
            }
        }
        .navigationTitle("Contacts")
        .task { await model.load() }
        .confirmationDialog("Turn off contact matching?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Turn off and delete", role: .destructive) { Task { await model.turnOff() } }
            Button("Keep it on", role: .cancel) {}
        } message: {
            Text("We delete your number and every code from your contacts, right away. Requests you sent and "
                + "haven't heard back on are withdrawn. Friends you've already added stay your friends. To also "
                + "stop \(appName) reading your contacts, change it in your phone's Settings.")
        }
        .alert("Name friends match on", isPresented: $editingName) {
            TextField("First name", text: $firstName)
            TextField("Last name", text: $lastName)
            Button("Save") { Task { await model.setName(firstName: firstName, lastName: lastName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the name your friends would save you under.")
        }
    }

    @ViewBuilder
    private func on(_ state: ContactMatching, _ colors: DesignTokens.Colors) -> some View {
        Section {
            LabeledContent("Find friends from contacts", value: "On")
        } footer: {
            Text("People who turned this on and have your number saved can find you, and you can find them.")
        }
        Section("How friends find you") {
            LabeledContent("Your number") {
                Label(state.phoneNumber ?? "", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color(colors.success))
                    .accessibilityLabel("\(state.phoneNumber ?? ""), verified")
            }
            Button {
                firstName = state.firstName ?? ""
                lastName = state.lastName ?? ""
                editingName = true
            } label: {
                LabeledContent("Name friends match on",
                               value: [state.firstName, state.lastName].compactMap { $0 }.joined(separator: " "))
            }
        }
        Section {
            if let checked = state.lastCheckedAt {
                LabeledContent("Last checked") {
                    Text("\(checked.formatted(.relative(presentation: .named))) · \(state.contactsChecked) contacts")
                }
            }
            Button("Check again") {
                Task {
                    guard state.canCheck() else {
                        notice = "You can check again tomorrow."
                        return
                    }
                    notice = await model.checkContacts() ? "Checked just now." : nil
                }
            }
            .disabled(model.working)
            if model.contactsDenied {
                Text("\(appName) can't see your contacts. Turn it on in Settings › \(appName) › Contacts.")
                    .font(.footnote)
            }
            if let message = model.error ?? notice { Text(message).font(.footnote) }
        } header: {
            Text("Your contacts")
        } footer: {
            Text("You can check once a day. Contacts with only a first name are always skipped.")
        }
        Section {
            Button("Turn off and delete my codes", role: .destructive) { confirmingOff = true }
        }
    }
}
#endif
#endif
