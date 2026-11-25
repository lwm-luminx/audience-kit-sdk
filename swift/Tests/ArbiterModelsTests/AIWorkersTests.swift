import Foundation
import Testing
@testable import ArbiterModels

/// The console's Workers page as the Mac reads it: each worker's hours worked out as the server does them.
@Suite struct AIWorkersTests {
    /// A moment in UTC: 2026-11-10 is a Tuesday (weekday 2).
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func alwaysCoversEveryMoment() {
        #expect(AIWorkerSchedule().covers(at(10, 3)))
    }

    @Test func hoursCoverTheirDaysFromStartUpToEnd() {
        let schedule = AIWorkerSchedule(mode: "hours", days: [2], start: "09:00", end: "17:00", timeZone: "Etc/UTC")
        #expect(schedule.covers(at(10, 9)))
        #expect(schedule.covers(at(10, 16, 59)))
        #expect(!schedule.covers(at(10, 17)))
        #expect(!schedule.covers(at(10, 8, 59)))
        #expect(!schedule.covers(at(11, 10)))  // Wednesday
    }

    @Test func overnightHoursBelongToTheDayTheyStart() {
        let schedule = AIWorkerSchedule(mode: "hours", days: [2], start: "22:00", end: "04:00", timeZone: "Etc/UTC")
        #expect(schedule.covers(at(10, 23)))
        #expect(schedule.covers(at(11, 3, 59)))  // Wednesday early, from Tuesday's night
        #expect(!schedule.covers(at(11, 4)))
        #expect(!schedule.covers(at(10, 3)))  // Tuesday early belongs to Monday, which isn't chosen
    }

    @Test func theSameStartAndEndIsTheWholeDay() {
        let schedule = AIWorkerSchedule(mode: "hours", days: [2], start: "00:00", end: "00:00", timeZone: "Etc/UTC")
        #expect(schedule.covers(at(10, 0)))
        #expect(schedule.covers(at(10, 23, 59)))
        #expect(!schedule.covers(at(11, 0)))
    }

    @Test func hoursAreInTheScheduleTimeZone() {
        // 09:00 to 17:00 in Los Angeles (UTC-8 in November) is 17:00 to 01:00 UTC.
        let schedule = AIWorkerSchedule(mode: "hours", days: [2], start: "09:00", end: "17:00",
                                        timeZone: "America/Los_Angeles")
        #expect(schedule.covers(at(10, 17)))
        #expect(!schedule.covers(at(10, 9)))
    }

    @Test func readsTheWorkersFromTheConsoleSettings() throws {
        let fromAPI = """
        {"configured": true, "workers": {
          "glam": {"enabled": false, "workingNow": false, "provider": "device", "tools": ["room_info"]},
          "research": {"enabled": true, "workingNow": true, "provider": "anthropic", "model": "claude",
                       "schedule": {"mode": "hours", "days": [2], "start": "09:00", "end": "17:00",
                                    "timeZone": "Etc/UTC", "everyMinutes": 15}},
          "someday": {"enabled": true}
        }}
        """
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(fromAPI.utf8))
        #expect(!server.working(.glam, at: at(10, 12)))
        #expect(server.working(.research, at: at(10, 12)))
        #expect(!server.working(.research, at: at(10, 20)))
        // Moderation isn't described, so it works as before.
        #expect(server.working(.moderation, at: at(10, 12)))
        #expect(server.worker(.research)?.schedule?.every == .seconds(15 * 60))
        #expect(server.worker(.research)?.onDevice == false)
        #expect(server.worker(.glam)?.onDevice == true)
        #expect(server.worker(.glam)?.line(.glam) == "AI host: off in the console")
    }

    @Test func anAPIBeforeTheWorkersPageLeavesEveryWorkerWorking() throws {
        let server = try JSONDecoder().decode(ServerEngineSettings.self, from: Data(#"{"configured": false}"#.utf8))
        #expect(server.workers == nil)
        for key in AIWorkerKey.allCases { #expect(server.working(key)) }
        let none: ServerEngineSettings? = nil
        #expect(none.working(.research))
    }
}
