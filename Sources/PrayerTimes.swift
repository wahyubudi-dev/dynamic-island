import Foundation

enum Prayer: Int, CaseIterable, Identifiable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }

    /// Prayers shown in the island (sunrise omitted).
    static var displayed: [Prayer] { [.fajr, .dhuhr, .asr, .maghrib, .isha] }

    var isDisplayed: Bool { self != .sunrise }
}

struct PrayerTime: Identifiable {
    let prayer: Prayer
    let date: Date
    var id: Prayer { prayer }
}

struct PrayerSettings {
    var fajrAngle: Double
    var ishaAngle: Double
    var asrFactor: Double

    static let kemenag = PrayerSettings(fajrAngle: 20, ishaAngle: 18, asrFactor: 1)
    static let mwl = PrayerSettings(fajrAngle: 18, ishaAngle: 17, asrFactor: 1)

    static func automatic(for timeZone: TimeZone) -> PrayerSettings {
        let id = timeZone.identifier
        let indonesia = id.hasPrefix("Asia/Jakarta")
            || id.hasPrefix("Asia/Pontianak")
            || id.hasPrefix("Asia/Makassar")
            || id.hasPrefix("Asia/Jayapura")
        return indonesia ? .kemenag : .mwl
    }

    var name: String {
        self.fajrAngle == 20 ? "Kemenag" : "MWL"
    }
}

enum PrayerCalculator {
    private static let degrees = Double.pi / 180

    static func times(
        for date: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone,
        settings: PrayerSettings = .kemenag
    ) -> [PrayerTime] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return [] }

        let jd = julianDate(year: year, month: month, day: day)
        let latitudeRad = latitude * degrees

        func sunPosition(_ time: Double) -> (declination: Double, equation: Double) {
            solarPosition(julianDate: jd + time / 24)
        }

        func midDay(_ time: Double) -> Double {
            let equation = sunPosition(time).equation
            return fixHour(12 - equation)
        }

        func sunAngleTime(_ angle: Double, _ time: Double, counterClockwise: Bool) -> Double? {
            let declination = sunPosition(time).declination
            let noon = midDay(time)
            let numerator = -sin(angle * degrees)
                - sin(declination * degrees) * sin(latitudeRad)
            let denominator = cos(declination * degrees) * cos(latitudeRad)
            guard abs(denominator) > 0.0001 else { return nil }
            let cosT = numerator / denominator
            guard cosT >= -1, cosT <= 1 else { return nil }
            let hours = acos(cosT) / degrees / 15
            return noon + (counterClockwise ? -hours : hours)
        }

        func asrTime(_ factor: Double, _ time: Double) -> Double? {
            let declination = sunPosition(time).declination
            let angle = -atan(1 / (factor + tan(abs(latitude - declination) * degrees))) / degrees
            return sunAngleTime(angle, time, counterClockwise: false)
        }

        let dhuhr = midDay(12)
        guard let sunrise = sunAngleTime(0.833, dhuhr, counterClockwise: true),
              let sunset = sunAngleTime(0.833, dhuhr, counterClockwise: false),
              let fajr = sunAngleTime(settings.fajrAngle, dhuhr, counterClockwise: true),
              let isha = sunAngleTime(settings.ishaAngle, dhuhr, counterClockwise: false),
              let asr = asrTime(settings.asrFactor, dhuhr) else {
            return []
        }

        let timezoneOffset = Double(timeZone.secondsFromGMT(for: date)) / 3600
        let shift = timezoneOffset - longitude / 15
        let startOfDay = calendar.startOfDay(for: date)

        func makeDate(_ hours: Double) -> Date {
            // Round to the nearest minute.
            let seconds = (hours + shift) * 3600
            let rounded = (seconds / 60).rounded() * 60
            return startOfDay.addingTimeInterval(rounded)
        }

        return [
            PrayerTime(prayer: .fajr, date: makeDate(fajr)),
            PrayerTime(prayer: .sunrise, date: makeDate(sunrise)),
            PrayerTime(prayer: .dhuhr, date: makeDate(dhuhr)),
            PrayerTime(prayer: .asr, date: makeDate(asr)),
            PrayerTime(prayer: .maghrib, date: makeDate(sunset)),
            PrayerTime(prayer: .isha, date: makeDate(isha)),
        ]
    }

    // MARK: - Astronomy

    private static func julianDate(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = floor(Double(y) / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716))
            + floor(30.6001 * Double(m + 1))
            + Double(day)
            + b
            - 1524.5
    }

    private static func solarPosition(julianDate: Double) -> (declination: Double, equation: Double) {
        let d = julianDate - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * sin(g * degrees) + 0.020 * sin(2 * g * degrees))
        let e = 23.439 - 0.00000036 * d
        let ra = atan2(cos(e * degrees) * sin(l * degrees), cos(l * degrees)) / degrees / 15
        let equation = q / 15 - fixHour(ra)
        let declination = asin(sin(e * degrees) * sin(l * degrees)) / degrees
        return (declination, equation)
    }

    private static func fixAngle(_ angle: Double) -> Double {
        angle - 360 * floor(angle / 360)
    }

    private static func fixHour(_ hour: Double) -> Double {
        hour - 24 * floor(hour / 24)
    }
}
