import Foundation

/// Local sunrise and sunset from the NOAA solar equations. The location is
/// estimated from the current time zone, so no location permission is needed.
enum SolarClock {
    /// Minutes after local midnight, or the 7:00 / 19:00 fallback.
    static func today(_ date: Date = Date(), zone: TimeZone = .current) -> (sunrise: Int, sunset: Int) {
        guard let (lat, lon) = coordinates(for: zone) else { return (7 * 60, 19 * 60) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let gamma = 2 * Double.pi / 365 * (dayOfYear - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let latRad = lat * .pi / 180
        let cosHA = cos(90.833 * .pi / 180) / (cos(latRad) * cos(decl)) - tan(latRad) * tan(decl)
        guard cosHA > -1, cosHA < 1 else { return (7 * 60, 19 * 60) } // polar day or night
        let haDeg = acos(cosHA) * 180 / .pi
        let offset = Double(zone.secondsFromGMT(for: date)) / 60
        let rise = 720 - 4 * (lon + haDeg) - eqTime + offset
        let set = 720 - 4 * (lon - haDeg) - eqTime + offset
        return (wrap(rise), wrap(set))
    }

    private static func wrap(_ minutes: Double) -> Int {
        (Int(minutes.rounded()) % 1440 + 1440) % 1440
    }

    /// The last zone looked up and its answer. The schedule is evaluated on
    /// every state change (each 30 s tick, app switch and slider step), and
    /// zone.tab is a few hundred lines, so read it once per zone rather than
    /// every time. Main thread only.
    private static var cached: (zone: String, coordinates: (Double, Double)?)?

    /// Reference coordinates for the zone from the system zone table, else a
    /// longitude implied by the UTC offset at a mid latitude.
    static func coordinates(for zone: TimeZone) -> (Double, Double)? {
        if let cached, cached.zone == zone.identifier { return cached.coordinates }
        let found = lookup(zone)
        cached = (zone.identifier, found)
        return found
    }

    private static func lookup(_ zone: TimeZone) -> (Double, Double)? {
        if let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) {
            for line in table.split(separator: "\n") where !line.hasPrefix("#") {
                let fields = line.split(separator: "\t")
                if fields.count >= 3, fields[2] == zone.identifier, let coords = parse(String(fields[1])) {
                    return coords
                }
            }
        }
        let hours = Double(zone.secondsFromGMT()) / 3600
        return (40, hours * 15)
    }

    /// Parses ISO 6709 "+DDMM-DDDMM" or "+DDMMSS-DDDMMSS".
    static func parse(_ text: String) -> (Double, Double)? {
        guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func degrees(_ part: Substring, degreeDigits: Int) -> Double? {
            let sign: Double = part.first == "-" ? -1 : 1
            let digits = Array(part.dropFirst())
            guard digits.count >= degreeDigits + 2,
                  let d = Double(String(digits[0..<degreeDigits])),
                  let m = Double(String(digits[degreeDigits..<degreeDigits + 2])) else { return nil }
            let s = digits.count >= degreeDigits + 4 ? Double(String(digits[(degreeDigits + 2)..<(degreeDigits + 4)])) ?? 0 : 0
            return sign * (d + m / 60 + s / 3600)
        }
        guard let lat = degrees(text[..<split], degreeDigits: 2),
              let lon = degrees(text[split...], degreeDigits: 3) else { return nil }
        return (lat, lon)
    }

    static func format(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
