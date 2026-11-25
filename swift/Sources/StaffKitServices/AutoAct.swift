import Foundation
import AudienceCore
import StaffKitCore

// The automatic act (Rick, 2026-10-31): the staff apps edit an event's lineup as one list of who's on, in order,
// with intermissions between them. Underneath it's the lineup model the console edits (doc/LINEUP_MODEL.md): each
// row is a scene of an act, the lineup's last act takes new scenes (one is made when there's none), and an
// intermission between two rows is a break after the scene before it. Lineups built on the console with several
// acts keep them, under each act's name.

/// One row of a lineup's list: a scene (or an act with no scene rows, which runs as one scene of its people), an
/// act's name over its scenes, or a break or other entry at its own place.
public enum LineupListRow: Hashable, Sendable, Identifiable {
    /// `scene` nil: an act with no scene rows. `number` counts scenes from 1 down the whole lineup.
    case scene(act: ZoneLineupEntry, scene: ShowLineupEntry.Scene?, number: Int)
    /// An act's name, over its scenes: shown once a lineup's acts need telling apart.
    case act(ZoneLineupEntry)
    /// A break (between acts, or after a scene) or a clock-run entry (a host or DJ on by the clock).
    case entry(ZoneLineupEntry)

    public var id: String {
        switch self {
        case .scene(let act, let scene, _): "scene-\(act.id)-\(scene?.id ?? "")"
        case .act(let act): "act-\(act.id)"
        case .entry(let entry): "entry-\(entry.id)"
        }
    }

    /// Who's on a scene row: its performers, else its act's people.
    public var performers: [VenueEvent.Person] {
        guard case .scene(let act, let scene, _) = self else { return [] }
        let people = scene?.people ?? []
        return people.isEmpty ? act.appearance.people : people
    }
}

extension ZoneLineup {
    /// The acts the show steps through: not a host, MC or DJ on by the clock (the running order's host entries).
    public var steppedActs: [ZoneLineupEntry] { acts.filter { !$0.isClockRun } }

    /// The act a new scene joins: the last one the show steps through.
    public var automaticAct: ZoneLineupEntry? { steppedActs.last }

    /// Whether the list names its acts: with more than one, when one has a billing and several scenes, or more than
    /// one has several scenes (built that way on the console). One act, or acts of one scene each (which the running
    /// order used to make), read as a plain list.
    public var namesActs: Bool {
        let acts = steppedActs
        guard acts.count > 1 else { return false }
        return acts.contains { !($0.appearance.title ?? "").isEmpty && $0.show.scenes.count > 1 } || acts.filter { $0.show.scenes.count > 1 }.count > 1
    }

    /// The lineup as one list, in running order.
    public var listRows: [LineupListRow] {
        var rows: [LineupListRow] = []
        var number = 0
        let names = namesActs
        for entry in topLevel {
            guard entry.isAct, !entry.isClockRun else { rows.append(.entry(entry)); continue }
            if names { rows.append(.act(entry)) }
            let breaks = self.breaks(in: entry)
            if entry.show.scenes.isEmpty {
                number += 1
                rows.append(.scene(act: entry, scene: nil, number: number))
            }
            for scene in entry.show.scenes {
                number += 1
                rows.append(.scene(act: entry, scene: scene, number: number))
                rows += (breaks[scene.id] ?? []).map(LineupListRow.entry)
            }
        }
        return rows
    }

    /// The scene a new intermission follows: the last scene of the last act, so it sits after the last row.
    public var lastScene: ShowLineupEntry.Scene? { automaticAct?.show.scenes.last }
}

/// Changes to a lineup's list, as appearance inputs.
public enum LineupList {
    /// A scene's input that keeps it as it is (its ID only).
    static func kept(_ scene: ShowLineupEntry.Scene) -> GraphQLValue { .object(["id": .string(scene.id)]) }

    static func newScene(_ performers: [VenueEvent.Person], title: String?) -> GraphQLValue {
        var input: [String: GraphQLValue] = [
            "performerIds": .array(performers.map { .string($0.id) }),
            "performerId": performers.first.map { .string($0.id) } ?? .null,
        ]
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { input["title"] = .string(title) }
        return .object(input)
    }

    /// An act's scenes as kept inputs; an act with no scene rows gets one scene of its people, so a scene added after
    /// it doesn't take its place.
    static func keptScenes(of act: ZoneLineupEntry) -> [GraphQLValue] {
        act.show.scenes.isEmpty ? [newScene(act.appearance.people, title: nil)] : act.show.scenes.map(kept)
    }

    /// Everyone on the act's scenes, in order, once each, plus `adding`: its billing, which the running order and
    /// shipped apps read.
    static func billing(_ act: ZoneLineupEntry, adding: [VenueEvent.Person] = [], removing scene: String? = nil) -> GraphQLValue {
        var seen = Set<String>()
        let scenes = act.show.scenes.filter { $0.id != scene }
        let everyone = (scenes.isEmpty && scene == nil ? act.appearance.people : scenes.flatMap(\.people)) + adding
        let people = everyone.filter { seen.insert($0.id).inserted }
        return .array(people.map { .string($0.id) })
    }

    /// Fields that add `performers` as a new scene at the end of `act`.
    public static func appending(_ performers: [VenueEvent.Person], title: String? = nil, to act: ZoneLineupEntry) -> [String: GraphQLValue] {
        ["scenes": .array(keptScenes(of: act) + [newScene(performers, title: title)]),
         "personIds": billing(act, adding: performers)]
    }

    /// Fields for the lineup's first act, which takes its first scene: in order, run from the host.
    public static func firstAct(_ performers: [VenueEvent.Person], title: String? = nil, on lineup: ZoneLineup) -> [String: GraphQLValue] {
        var fields: [String: GraphQLValue] = [
            "kind": .string("ACT"), "role": .string("PERFORMER"), "startTiming": .string("NONE"), "endTiming": .string("ADVANCE"),
            "night": .string(lineup.night), "lineupId": .string(lineup.id),
            "personIds": .array(performers.map { .string($0.id) }),
            "scenes": .array([newScene(performers, title: title)]),
        ]
        if let event = lineup.event { fields["eventId"] = .string(event.id) }
        return fields
    }

    /// Fields for an intermission on `lineup`: after `scene` (between two rows), or at the end when nil.
    public static func intermission(on lineup: ZoneLineup, after scene: String?, minutes: Int = 15) -> [String: GraphQLValue] {
        var fields: [String: GraphQLValue] = [
            "kind": .string("INTERMISSION"), "startTiming": .string("NONE"), "endTiming": .string("ADVANCE"),
            "durationMinutes": .int(minutes), "night": .string(lineup.night), "lineupId": .string(lineup.id),
        ]
        if let event = lineup.event { fields["eventId"] = .string(event.id) }
        if let scene { fields["afterSceneId"] = .string(scene) }
        return fields
    }

    /// Fields that take `scene` out of `act`. Nil when it's the act's only one: the act itself comes off.
    public static func removing(_ scene: String, from act: ZoneLineupEntry) -> [String: GraphQLValue]? {
        let rest = act.show.scenes.filter { $0.id != scene }
        guard !rest.isEmpty else { return nil }
        return ["scenes": .array(rest.map(kept)), "personIds": billing(act, removing: scene)]
    }

    /// Fields that move one of `act`'s scenes to `offset` among them (as SwiftUI's `onMove` gives them).
    public static func moving(_ from: IndexSet, to offset: Int, in act: ZoneLineupEntry) -> [String: GraphQLValue] {
        let scenes = act.show.scenes
        let moved = from.map { scenes[$0] }
        var rest = scenes.enumerated().filter { !from.contains($0.offset) }.map(\.element)
        let at = offset - from.filter { $0 < offset }.count
        rest.insert(contentsOf: moved, at: max(0, min(at, rest.count)))
        return ["scenes": .array(rest.map(kept))]
    }

    /// Fields that change one scene's performers and title, keeping the act's others as they are.
    public static func changing(_ scene: String, to performers: [VenueEvent.Person], title: String, in act: ZoneLineupEntry) -> [String: GraphQLValue] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenes: [GraphQLValue] = act.show.scenes.map { existing in
            guard existing.id == scene else { return kept(existing) }
            return .object([
                "id": .string(existing.id), "title": trimmed.isEmpty ? .null : .string(trimmed),
                "performerIds": .array(performers.map { .string($0.id) }),
                "performerId": performers.first.map { .string($0.id) } ?? .null,
            ])
        }
        var seen = Set<String>()
        let people = act.show.scenes.flatMap { $0.id == scene ? performers : $0.people }.filter { seen.insert($0.id).inserted }
        return ["scenes": .array(scenes), "personIds": .array(people.map { .string($0.id) })]
    }
}
