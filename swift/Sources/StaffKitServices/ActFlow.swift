import Foundation
import AudienceCore
import StaffKitCore

// The advanced act editor (docs/ADVANCED_ACT_EDITOR.md): an act's flow as the show runs it. The host opens the act,
// each scene follows, the host takes the stage back between scenes unless a scene runs straight on to the next, a
// break sits after the scene it follows, and the host closes the act. The staff apps draw this as cards with a + on
// every seam; `LineupList` gains the inputs those seams send.

/// One card of an act's flow.
public enum ActFlowItem: Hashable, Sendable, Identifiable {
    public enum HostTurn: String, Sendable, Hashable { case opens, between, closes }
    /// The host has the stage: before the first scene, between two, or after the last. `after` is the scene before it.
    case host(HostTurn, after: String?)
    /// A scene, numbered within the act; nil for an act with no scene rows, which runs as one scene of its people.
    case scene(ShowLineupEntry.Scene?, number: Int)
    /// A break inside the act, after the scene before it.
    case pause(ZoneLineupEntry)

    public var id: String {
        switch self {
        case .host(let turn, let after): "host-\(turn.rawValue)-\(after ?? "")"
        case .scene(let scene, let number): "scene-\(scene?.id ?? "act")-\(number)"
        case .pause(let entry): "pause-\(entry.id)"
        }
    }
}

/// A seam of the flow, where a + adds something: a scene at `index` among the act's scenes, and, after a scene, a
/// break there.
public struct ActFlowSeam: Hashable, Sendable, Identifiable {
    /// Where a new scene goes among the act's scenes (0 = first).
    public let index: Int
    /// The scene before the seam; nil before the first scene, where only a scene can go.
    public let afterScene: String?
    public init(index: Int, afterScene: String?) { self.index = index; self.afterScene = afterScene }
    public var id: String { "seam-\(index)-\(afterScene ?? "")" }
}

extension ZoneLineup {
    /// Where `scene` goes when it ends: its own setting, else its act's, else the lineup's, else back to the host.
    public func endsTo(of scene: ShowLineupEntry.Scene?, in act: ZoneLineupEntry) -> ShowEndsTo {
        scene?.endsTo ?? act.endsTo ?? sceneEndsTo ?? .host
    }

    /// The act's flow: host opens, scenes with the breaks after them, the host between (unless the scene or the last
    /// break after it runs straight on), and the host closes.
    public func flow(of act: ZoneLineupEntry) -> [ActFlowItem] {
        var items: [ActFlowItem] = [.host(.opens, after: nil)]
        let scenes = act.show.scenes
        guard !scenes.isEmpty else { return items + [.scene(nil, number: 1), .host(.closes, after: nil)] }
        let breaks = self.breaks(in: act)
        for (index, scene) in scenes.enumerated() {
            items.append(.scene(scene, number: index + 1))
            let after = breaks[scene.id] ?? []
            items += after.map(ActFlowItem.pause)
            if index == scenes.count - 1 {
                items.append(.host(.closes, after: scene.id))
            } else if (after.last.map { $0.endsTo ?? .host } ?? endsTo(of: scene, in: act)) == .host {
                items.append(.host(.between, after: scene.id))
            }
        }
        return items
    }

    /// The seams of the act's flow, in order: before the first scene, then after each scene (and the breaks after it).
    public func seams(of act: ZoneLineupEntry) -> [ActFlowSeam] {
        [ActFlowSeam(index: 0, afterScene: nil)] + act.show.scenes.enumerated().map { ActFlowSeam(index: $0.offset + 1, afterScene: $0.element.id) }
    }

    /// What runs at its own place after `act`: the next act, or the break between them.
    public func following(_ act: ZoneLineupEntry) -> ZoneLineupEntry? {
        let top = topLevel
        guard let index = top.firstIndex(where: { $0.id == act.id }), index + 1 < top.count else { return nil }
        return top[index + 1]
    }

    /// A scene's number down the whole lineup, as the list numbers them ("Scene 4").
    public func number(of scene: ShowLineupEntry.Scene?, in act: ZoneLineupEntry) -> Int? {
        for row in listRows {
            if case .scene(let other, let found, let number) = row, other.id == act.id, found?.id == scene?.id { return number }
        }
        return nil
    }
}

extension LineupList {
    /// Fields that put `performers` on as a new scene at `index` among `act`'s scenes (a seam's "A scene here").
    public static func inserting(_ performers: [VenueEvent.Person], title: String? = nil, at index: Int,
                                 in act: ZoneLineupEntry) -> [String: GraphQLValue] {
        var scenes = keptScenes(of: act)
        let at = max(0, min(index, scenes.count))
        scenes.insert(newScene(performers, title: title), at: at)
        var people = act.show.scenes.isEmpty ? [act.appearance.people] : act.show.scenes.map(\.people)
        people.insert(performers, at: at)
        var seen = Set<String>()
        return ["scenes": .array(scenes), "personIds": .array(people.flatMap { $0 }.filter { seen.insert($0.id).inserted }.map { .string($0.id) })]
    }

    /// The billing a set of scene drafts gives: everyone in them once, in order. A scene with no one named counts
    /// the act's people, as the show does.
    public static func billing(of scenes: [ShowEntryDraft.Scene], in act: ZoneLineupEntry) -> GraphQLValue {
        var seen = Set<String>()
        let people = scenes.flatMap { $0.performers.isEmpty ? act.appearance.people : $0.performers }.filter { seen.insert($0.id).inserted }
        return .array(people.map { .string($0.id) })
    }
}
