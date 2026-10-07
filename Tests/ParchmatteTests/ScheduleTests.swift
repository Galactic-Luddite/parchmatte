import XCTest
@testable import Parchmatte

/// The schedule rule with the clock, calendar and zone pinned (test plan
/// G3: custom hours across midnight, sun-based modes).
final class ScheduleTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute))!
    }

    private func resumes(_ mode: ScheduleMode, now: Date, custom: (Int, Int) = (9 * 60, 17 * 60),
                         zone: TimeZone? = nil) -> Int? {
        AppController.scheduleResumes(
            mode: mode, now: now, custom: (custom.0, custom.1), calendar: calendar, zone: zone ?? utc
        )
    }

    func testAlwaysNeverPauses() {
        XCTAssertNil(resumes(.always, now: at(3)))
        XCTAssertNil(resumes(.always, now: at(23, 59)))
    }

    func testCustomHoursWithinTheDay() {
        XCTAssertNil(resumes(.customHours, now: at(9)), "start is inclusive")
        XCTAssertNil(resumes(.customHours, now: at(12, 30)))
        XCTAssertEqual(resumes(.customHours, now: at(17)), 9 * 60, "end is exclusive")
        XCTAssertEqual(resumes(.customHours, now: at(8, 59)), 9 * 60)
        XCTAssertEqual(resumes(.customHours, now: at(0)), 9 * 60)
    }

    func testCustomHoursAcrossMidnight() {
        let night = (22 * 60, 6 * 60)
        XCTAssertNil(resumes(.customHours, now: at(23), custom: night))
        XCTAssertNil(resumes(.customHours, now: at(0, 30), custom: night))
        XCTAssertNil(resumes(.customHours, now: at(5, 59), custom: night))
        XCTAssertEqual(resumes(.customHours, now: at(6), custom: night), 22 * 60)
        XCTAssertEqual(resumes(.customHours, now: at(12), custom: night), 22 * 60)
    }

    func testZeroLengthWindowIsAlwaysOff() {
        XCTAssertEqual(resumes(.customHours, now: at(9), custom: (9 * 60, 9 * 60)), 9 * 60)
    }

    func testMinuteOfDayWindow() {
        XCTAssertTrue(AppController.minuteOfDay(600, isWithin: (540, 1020)))
        XCTAssertFalse(AppController.minuteOfDay(1020, isWithin: (540, 1020)))
        XCTAssertTrue(AppController.minuteOfDay(30, isWithin: (1320, 360)))
        XCTAssertTrue(AppController.minuteOfDay(1380, isWithin: (1320, 360)))
        XCTAssertFalse(AppController.minuteOfDay(720, isWithin: (1320, 360)))
    }

    func testSunModesAtNoonInNewYork() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let noon = local.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        // Daylight: sunrise-to-sunset is on; sunset-to-sunrise resumes at sunset (~20:31).
        XCTAssertNil(AppController.scheduleResumes(
            mode: .sunriseToSunset, now: noon, custom: (0, 0), calendar: local, zone: zone
        ))
        let resumes = try XCTUnwrap(AppController.scheduleResumes(
            mode: .sunsetToSunrise, now: noon, custom: (0, 0), calendar: local, zone: zone
        ))
        XCTAssertLessThanOrEqual(abs(resumes - (20 * 60 + 31)), 10, "resumes at \(resumes)")
    }
}
