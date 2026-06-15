import CoreLocation
import Foundation

struct SunWindow: Equatable {
    let sunrise: Date
    let sunset: Date

    func shouldEnableDarkMode(at date: Date = Date()) -> Bool {
        date < sunrise || date >= sunset
    }

    func timeOfDay(for date: Date, calendar: Calendar = .current) -> TimeOfDay? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }

    var sunriseDisplay: String {
        timeOfDay(for: sunrise)?.display ?? "sunrise"
    }

    var sunsetDisplay: String {
        timeOfDay(for: sunset)?.display ?? "sunset"
    }
}

final class SunScheduleProvider: NSObject, CLLocationManagerDelegate {
    var onUpdate: (() -> Void)?

    private let defaults: UserDefaults
    private var manager: CLLocationManager?
    private var pendingRequest = false
    private var status: Status = .idle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    var statusText: String {
        switch status {
        case .idle:
            return cachedCoordinate == nil ? "Location is not available" : "Location ready"
        case .requesting:
            return "Requesting location"
        case .ready:
            return "Location ready"
        case .unavailable(let message):
            return message
        }
    }

    var cachedCoordinate: CLLocationCoordinate2D? {
        guard defaults.object(forKey: DefaultsKey.latitude) != nil,
              defaults.object(forKey: DefaultsKey.longitude) != nil
        else { return nil }
        return CLLocationCoordinate2D(
            latitude: defaults.double(forKey: DefaultsKey.latitude),
            longitude: defaults.double(forKey: DefaultsKey.longitude)
        )
    }

    func requestLocation() {
        pendingRequest = true
        ensureManager()

        guard CLLocationManager.locationServicesEnabled() else {
            status = .unavailable("Location Services are off")
            notify()
            return
        }

        guard let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .requesting
            notify()
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            status = .requesting
            notify()
            manager.requestLocation()
        case .denied, .restricted:
            status = .unavailable(manager.authorizationStatus == .denied ? "Location access denied" : "Location access restricted")
            notify()
        @unknown default:
            status = .unavailable("Location is not available")
            notify()
        }
    }

    func sunWindow(for date: Date = Date(), calendar: Calendar = .current) -> SunWindow? {
        guard let coordinate = cachedCoordinate else { return nil }
        return SolarCalculator.sunWindow(on: date, coordinate: coordinate, calendar: calendar)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingRequest else { return }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            status = .requesting
            notify()
            manager.requestLocation()
        case .denied, .restricted:
            status = .unavailable(manager.authorizationStatus == .denied ? "Location access denied" : "Location access restricted")
            notify()
        case .notDetermined:
            break
        @unknown default:
            status = .unavailable("Location is not available")
            notify()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        pendingRequest = false
        defaults.set(location.coordinate.latitude, forKey: DefaultsKey.latitude)
        defaults.set(location.coordinate.longitude, forKey: DefaultsKey.longitude)
        defaults.set(Date(), forKey: DefaultsKey.updatedAt)
        status = .ready
        notify()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingRequest = false
        status = .unavailable("Location lookup failed")
        notify()
    }

    private func ensureManager() {
        guard manager == nil else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.manager = manager
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?()
        }
    }
}

private extension SunScheduleProvider {
    enum Status {
        case idle
        case requesting
        case ready
        case unavailable(String)
    }

    enum DefaultsKey {
        static let latitude = "switch.darkMode.location.latitude"
        static let longitude = "switch.darkMode.location.longitude"
        static let updatedAt = "switch.darkMode.location.updatedAt"
    }
}

enum SolarCalculator {
    static func sunWindow(on date: Date, coordinate: CLLocationCoordinate2D, calendar: Calendar) -> SunWindow? {
        guard let sunrise = sunEvent(on: date, coordinate: coordinate, calendar: calendar, isSunrise: true),
              let sunset = sunEvent(on: date, coordinate: coordinate, calendar: calendar, isSunrise: false)
        else { return nil }
        return SunWindow(sunrise: sunrise, sunset: sunset)
    }

    private static func sunEvent(
        on date: Date,
        coordinate: CLLocationCoordinate2D,
        calendar: Calendar,
        isSunrise: Bool
    ) -> Date? {
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }

        let longitudeHour = coordinate.longitude / 15.0
        let approximateTime = Double(dayOfYear) + ((isSunrise ? 6.0 : 18.0) - longitudeHour) / 24.0
        let meanAnomaly = 0.9856 * approximateTime - 3.289
        var trueLongitude = meanAnomaly
            + 1.916 * sin(degreesToRadians(meanAnomaly))
            + 0.020 * sin(2 * degreesToRadians(meanAnomaly))
            + 282.634
        trueLongitude = normalizeDegrees(trueLongitude)

        var rightAscension = radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
        rightAscension = normalizeDegrees(rightAscension)
        let longitudeQuadrant = floor(trueLongitude / 90.0) * 90.0
        let ascensionQuadrant = floor(rightAscension / 90.0) * 90.0
        rightAscension += longitudeQuadrant - ascensionQuadrant
        rightAscension /= 15.0

        let sinDeclination = 0.39782 * sin(degreesToRadians(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))
        let zenith = 90.833
        let cosHourAngle = (
            cos(degreesToRadians(zenith))
            - sinDeclination * sin(degreesToRadians(coordinate.latitude))
        ) / (cosDeclination * cos(degreesToRadians(coordinate.latitude)))

        guard (-1.0...1.0).contains(cosHourAngle) else { return nil }

        var hourAngle = radiansToDegrees(acos(cosHourAngle))
        if isSunrise {
            hourAngle = 360.0 - hourAngle
        }
        hourAngle /= 15.0

        let localMeanTime = hourAngle + rightAscension - 0.06571 * approximateTime - 6.622
        let universalTime = normalizeHours(localMeanTime - longitudeHour)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let localDay = calendar.dateComponents([.year, .month, .day], from: date)
        var utcDay = DateComponents()
        utcDay.calendar = utcCalendar
        utcDay.timeZone = utcCalendar.timeZone
        utcDay.year = localDay.year
        utcDay.month = localDay.month
        utcDay.day = localDay.day
        guard let utcMidnight = utcCalendar.date(from: utcDay) else { return nil }

        let candidate = utcMidnight.addingTimeInterval(universalTime * 3600)
        return align(candidate, toLocalDayOf: date, calendar: calendar)
    }

    private static func align(_ candidate: Date, toLocalDayOf date: Date, calendar: Calendar) -> Date {
        let candidateDay = calendar.startOfDay(for: candidate)
        let targetDay = calendar.startOfDay(for: date)
        if candidateDay < targetDay {
            return candidate.addingTimeInterval(24 * 60 * 60)
        }
        if candidateDay > targetDay {
            return candidate.addingTimeInterval(-24 * 60 * 60)
        }
        return candidate
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    private static func normalizeDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360.0)
        return value < 0 ? value + 360.0 : value
    }

    private static func normalizeHours(_ hours: Double) -> Double {
        let value = hours.truncatingRemainder(dividingBy: 24.0)
        return value < 0 ? value + 24.0 : value
    }
}
