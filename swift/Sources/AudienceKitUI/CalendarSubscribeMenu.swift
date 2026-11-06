#if canImport(SwiftUI)
import AudienceKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Subscribing to the person's calendar feed (``CalendarLinks``): in Calendar (webcal://), in Google Calendar, or by
/// copying the link.
public struct CalendarSubscribeMenu<Label: View>: View {
    let links: CalendarLinks
    let label: Label

    public init(links: CalendarLinks, @ViewBuilder label: () -> Label) {
        self.links = links
        self.label = label()
    }

    public var body: some View {
        Menu {
            CalendarSubscribeButtons(links: links)
        } label: {
            label
        }
    }
}

extension CalendarSubscribeMenu where Label == SwiftUI.Label<Text, Image> {
    /// The menu behind a "Subscribe" label with a calendar icon.
    public init(links: CalendarLinks, title: String = "Subscribe to Calendar") {
        self.init(links: links) { SwiftUI.Label(title, systemImage: "calendar.badge.plus") }
    }
}

/// The three ways to subscribe, as buttons for a menu or a confirmation dialog.
public struct CalendarSubscribeButtons: View {
    let links: CalendarLinks
    @Environment(\.openURL) private var openURL

    public init(links: CalendarLinks) { self.links = links }

    public var body: some View {
        Button("Subscribe in Calendar") { open(links.webcalURL) }
        Button("Add to Google Calendar") { open(links.googleURL) }
        Button("Copy Link") { CalendarPasteboard.copy(links.url) }
    }

    private func open(_ url: URL?) {
        if let url { openURL(url) }
    }
}

/// "Add to Calendar" on a venue: follows it in the person's one calendar feed, so every event there (a hackerspace's
/// meetups, a bar's weekly nights) shows up and stays up to date, then offers to subscribe to the feed for anyone
/// who hasn't yet. Tapping it again offers to stop.
///
/// ```swift
/// VenueCalendarButton(client: client, venueID: venue.id, venueName: venue.name)
/// ```
public struct VenueCalendarButton: View {
    let client: AudienceKitClient
    let venueID: String
    let venueName: String
    @State private var feed: CalendarFeed?
    @State private var working = false
    @State private var offeringSubscribe = false
    @State private var confirmingStop = false
    @State private var error: String?

    public init(client: AudienceKitClient, venueID: String, venueName: String) {
        self.client = client
        self.venueID = venueID
        self.venueName = venueName
    }

    var following: Bool { feed?.follows(venueID: venueID) == true }

    public var body: some View {
        Button {
            if following { confirmingStop = true } else { Task { await follow(true) } }
        } label: {
            SwiftUI.Label(following ? "In Your Calendar" : "Add to Calendar",
                          systemImage: following ? "calendar.badge.checkmark" : "calendar.badge.plus")
        }
        .disabled(working)
        .task(id: venueID) { feed = try? await client.calendarFeed() }
        .confirmationDialog("\(venueName)'s events are in your calendar feed", isPresented: $offeringSubscribe,
                            titleVisibility: .visible) {
            if let links = feed?.links { CalendarSubscribeButtons(links: links) }
            Button("Already Subscribed", role: .cancel) {}
        } message: {
            Text("If you already subscribed to your calendar feed, they show up on their own. Otherwise, subscribe once.")
        }
        .confirmationDialog("Remove \(venueName) from your calendar?", isPresented: $confirmingStop,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await follow(false) } }
            if let links = feed?.links { CalendarSubscribeButtons(links: links) }
        }
        .alert("Couldn't update your calendar",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func follow(_ on: Bool) async {
        working = true
        defer { working = false }
        do {
            feed = try await client.followVenueInCalendar(venueID: venueID, following: on)
            if on { offeringSubscribe = true }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum CalendarPasteboard {
    static func copy(_ text: String) {
        #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
#endif
