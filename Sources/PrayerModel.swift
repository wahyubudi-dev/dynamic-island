import Combine
import CoreLocation
import Foundation

final class PrayerModel: ObservableObject {
    @Published private(set) var today: [PrayerTime] = []
    @Published private(set) var tomorrow: [PrayerTime] = []
    @Published private(set) var locationName = ""
    @Published private(set) var hasLocation = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var methodName = "Kemenag"

    let locationService = LocationService()

    private var cancellables: Set<AnyCancellable> = []
    private var dayTimer: Timer?
    private var lastDay: Date?
    private var lastLocationRequest = Date()

    init() {
        locationService.$coordinate
            .receive(on: RunLoop.main)
            .sink { [weak self] coordinate in
                guard let self, let coordinate else { return }
                self.hasLocation = true
                self.recompute(coordinate)
            }
            .store(in: &cancellables)

        locationService.$placeName
            .receive(on: RunLoop.main)
            .sink { [weak self] name in self?.locationName = name }
            .store(in: &cancellables)

        locationService.$authorization
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.authorization = status }
            .store(in: &cancellables)

        if let coordinate = locationService.coordinate {
            hasLocation = true
            recompute(coordinate)
        }

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
    }

    deinit {
        dayTimer?.invalidate()
    }

    func retry() {
        locationService.requestLocation()
    }

    func openSettings() {
        locationService.openSettings()
    }

    /// Next prayer after `date`, including tomorrow's Fajr after Isha.
    func nextPrayer(after date: Date) -> PrayerTime? {
        (today + tomorrow)
            .filter { $0.prayer.isDisplayed && $0.date > date }
            .min { $0.date < $1.date }
    }

    var timeZone: TimeZone { .current }

    private func tick() {
        let now = Date()
        let day = Calendar.current.startOfDay(for: now)
        if day != lastDay, let coordinate = locationService.coordinate {
            recompute(coordinate)
        }
        if now.timeIntervalSince(lastLocationRequest) > 1800 {
            lastLocationRequest = now
            locationService.requestLocation()
        }
    }

    private func recompute(_ coordinate: CLLocationCoordinate2D) {
        let timeZone = TimeZone.current
        let settings = PrayerSettings.automatic(for: timeZone)
        methodName = settings.name

        let calendar = Calendar.current
        let now = Date()
        lastDay = calendar.startOfDay(for: now)

        today = PrayerCalculator.times(
            for: now,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZone: timeZone,
            settings: settings
        )

        let summary = today.map { "\($0.prayer.name)=\($0.date.formatted(date: .omitted, time: .shortened))" }
        NSLog("[prayer] %@ %@", settings.name, summary.joined(separator: " "))

        if let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) {
            tomorrow = PrayerCalculator.times(
                for: tomorrowDate,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZone: timeZone,
                settings: settings
            )
        } else {
            tomorrow = []
        }
    }
}
