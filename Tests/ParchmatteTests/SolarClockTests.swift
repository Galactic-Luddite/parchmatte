import XCTest
@testable import Parchmatte

/// Sunrise and sunset from the NOAA equations, with the zone pinned so the
/// result doesn't depend on the machine running the tests.
final class SolarClockTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testParsesISO6709DegreesMinutes() throws {
        let (lat, lon) = try XCTUnwrap(SolarClock.parse("+4043-07400"))
        XCTAssertEqual(lat, 40 + 43.0 / 60, accuracy: 0.001)
        XCTAssertEqual(lon, -74.0, accuracy: 0.001)
    }

    func testParsesISO6709WithSeconds() throws {
        let (lat, lon) = try XCTUnwrap(SolarClock.parse("-3352+15113"))
        XCTAssertEqual(lat, -(33 + 52.0 / 60), accuracy: 0.001)
        XCTAssertEqual(lon, 151 + 13.0 / 60, accuracy: 0.001)
        let (lat2, lon2) = try XCTUnwrap(SolarClock.parse("+404330-0740015"))
        XCTAssertEqual(lat2, 40 + 43.0 / 60 + 30.0 / 3600, accuracy: 0.0001)
        XCTAssertEqual(lon2, -(74 + 15.0 / 3600), accuracy: 0.0001)
    }

    func testRejectsMalformedCoordinates() {
        XCTAssertNil(SolarClock.parse(""))
        XCTAssertNil(SolarClock.parse("+40"))
        XCTAssertNil(SolarClock.parse("banana"))
    }

    func testNewYorkMidsummer() throws {
        // NOAA for 40.71 N, 74.0 W on 2026-06-21: sunrise 5:25, sunset 20:31 EDT.
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let sun = SolarClock.today(date(2026, 6, 21, hour: 12, in: zone), zone: zone)
        XCTAssertLessThanOrEqual(abs(sun.sunrise - (5 * 60 + 25)), 10, "sunrise \(sun.sunrise)")
        XCTAssertLessThanOrEqual(abs(sun.sunset - (20 * 60 + 31)), 10, "sunset \(sun.sunset)")
    }

    func testZoneMissingFromTableFallsBackToOffsetLongitude() throws {
        // Etc zones are not in zone.tab: latitude 40, longitude from the offset.
        let zone = try XCTUnwrap(TimeZone(identifier: "Etc/GMT+5"))
        let (lat, lon) = try XCTUnwrap(SolarClock.coordinates(for: zone))
        XCTAssertEqual(lat, 40, accuracy: 0.001)
        XCTAssertEqual(lon, -75, accuracy: 0.001)
    }

    func testPolarDayFallsBackToFixedHours() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Arctic/Longyearbyen"))
        // Only meaningful when the table knows the zone (latitude 78 N).
        guard let (lat, _) = SolarClock.coordinates(for: zone), lat > 70 else {
            throw XCTSkip("zone.tab on this machine has no Arctic/Longyearbyen row")
        }
        let sun = SolarClock.today(date(2026, 6, 21, hour: 12, in: zone), zone: zone)
        XCTAssertEqual(sun.sunrise, 7 * 60)
        XCTAssertEqual(sun.sunset, 19 * 60)
    }

    func testCoordinatesAreCachedPerZone() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let first = try XCTUnwrap(SolarClock.coordinates(for: zone))
        let second = try XCTUnwrap(SolarClock.coordinates(for: zone))
        XCTAssertEqual(first.0, second.0)
        XCTAssertEqual(first.1, second.1)
        XCTAssertEqual(first.0, 51.5, accuracy: 0.2)
    }
}
