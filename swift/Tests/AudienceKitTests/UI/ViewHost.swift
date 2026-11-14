// Hosts AudienceKitUI's SwiftUI views in a real window for the view tests. macOS only: `swift test` runs there, and
// Linux has no SwiftUI (the Linux job builds these files to nothing).
//
// SwiftUI on macOS doesn't build its accessibility tree for an in-process caller (the typed and the attribute-based
// accessibility APIs both come back empty under `swift test`), so `texts` is usually empty here and the tests check
// what can be measured: that a view drew, how tall it laid out, and how that changes with its state. `texts` is kept
// for when it does answer (a Mac with an assistive app connected).
#if canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI

@MainActor
final class ViewHost {
    let window: NSWindow
    let view: NSView

    init<Content: View>(_ content: Content, size: CGSize = CGSize(width: 420, height: 900),
                        colorScheme: ColorScheme = .light, dynamicType: DynamicTypeSize = .large) {
        _ = NSApplication.shared
        let root = content
            .frame(width: size.width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicType)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        self.window = window
        view = hosting
    }

    /// Lets the view's tasks run and lays it out again, until `condition` holds or `timeout` passes.
    @discardableResult
    func settle(timeout: Duration = .milliseconds(300), until condition: () -> Bool = { false }) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            view.display()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// How tall the view laid out, at the window's width.
    var height: CGFloat {
        view.layoutSubtreeIfNeeded()
        return view.fittingSize.height
    }

    /// Whether the view drew anything: it laid out with some height.
    var drewSomething: Bool { height > 1 }

    /// Waits until some text on screen contains `text`.
    @discardableResult
    func waitFor(_ text: String, timeout: Duration = .seconds(3)) async -> Bool {
        let found = await settle(timeout: timeout) { self.contains(text) }
        if !found { print("ViewHost: no \"\(text)\" among \(texts)") }
        return found
    }

    /// What the accessibility API says about one element: SwiftUI's are `NSView`s or `NSAccessibilityElement`s.
    private struct Info {
        var label: String?
        var title: String?
        var value: String?
        var identifier: String?
        var role: NSAccessibility.Role?
        var children: [Any]
        var press: () -> Bool
    }

    /// SwiftUI on macOS answers the attribute-based accessibility API (the one assistive apps use) even where the
    /// typed `NSAccessibility` methods come back empty, so this reads that one.
    private func info(_ object: NSObject) -> Info? {
        func attribute(_ name: NSAccessibility.Attribute) -> Any? {
            object.accessibilityAttributeValue(name)
        }
        let role = (attribute(.role) as? String).map(NSAccessibility.Role.init(rawValue:))
        return Info(label: attribute(.description) as? String, title: attribute(.title) as? String,
                    value: attribute(.value) as? String, identifier: attribute(.identifier) as? String,
                    role: role, children: attribute(.children) as? [Any] ?? [],
                    press: {
                        guard object.accessibilityActionNames().contains(.press) else { return false }
                        object.accessibilityPerformAction(.press)
                        return true
                    })
    }

    /// Every accessibility element under the window.
    var elements: [NSObject] {
        var found: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 80, seen.insert(ObjectIdentifier(object)).inserted else { return }
            found.append(object)
            for child in info(object)?.children ?? [] {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
            if let view = object as? NSView {
                for subview in view.subviews { visit(subview, depth: depth + 1) }
            }
        }
        visit(view, depth: 0)
        return found
    }

    /// Every accessibility label, title, value and identifier on screen.
    var texts: [String] {
        elements.compactMap(info).flatMap { info in
            [info.label, info.title, info.value, info.identifier].compactMap { $0 }.filter { !$0.isEmpty }
        }
    }

    func contains(_ text: String) -> Bool {
        texts.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    /// Presses (as VoiceOver does) the first button whose label or title is `label`. Returns whether one was found.
    @discardableResult
    func press(_ label: String) -> Bool {
        for info in elements.compactMap(info) where [info.label, info.title].contains(label) && info.role == .button {
            if info.press() { return true }
        }
        return false
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}
#endif
