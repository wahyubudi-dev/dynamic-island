import CoreLocation
import SwiftUI

private let prayerAccent = Color(red: 0.33, green: 0.82, blue: 0.60)

private let prayerTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter
}()

struct PrayerPage: View {
    @ObservedObject var model: PrayerModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            PrayerPageContent(
                today: model.today,
                next: model.nextPrayer(after: context.date),
                now: context.date,
                locationName: model.locationName,
                hasLocation: model.hasLocation,
                authorization: model.authorization,
                methodName: model.methodName,
                onRetry: model.retry,
                onOpenSettings: model.openSettings
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

struct PrayerPageContent: View {
    let today: [PrayerTime]
    let next: PrayerTime?
    let now: Date
    let locationName: String
    let hasLocation: Bool
    let authorization: CLAuthorizationStatus
    let methodName: String
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    private var displayTimes: [PrayerTime] {
        today.filter { $0.prayer.isDisplayed }
    }

    private var placeLabel: String {
        locationName.isEmpty ? "Current location" : locationName
    }

    private var locationDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    var body: some View {
        Group {
            if hasLocation, !displayTimes.isEmpty {
                schedule
            } else if hasLocation {
                message(
                    icon: "exclamationmark.triangle",
                    title: "Unable to calculate",
                    subtitle: "Prayer times are unavailable for this latitude today.",
                    button: nil
                )
            } else {
                message(
                    icon: "location.slash",
                    title: locationDenied ? "Location access off" : "Location needed",
                    subtitle: locationDenied
                        ? "Enable location access to show today's prayer times."
                        : "Allow location access to calculate today's prayer times.",
                    button: locationDenied ? "Open Settings" : "Allow location"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Schedule

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PRAYER TIMES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.38))
                Spacer(minLength: 4)
                Image(systemName: "location.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.3))
                Text(placeLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                ForEach(displayTimes) { time in
                    prayerCard(time)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(prayerAccent)
                Text(nextLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text(methodName)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(.horizontal, 2)
    }

    private func prayerCard(_ time: PrayerTime) -> some View {
        let isNext = next?.id == time.id
        return VStack(spacing: 2) {
            Text(time.prayer.name.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(isNext ? prayerAccent : .white.opacity(0.42))
                .lineLimit(1)
            Text(timeText(time.date))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isNext ? 1 : 0.82))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isNext ? prayerAccent.opacity(0.16) : Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isNext ? prayerAccent.opacity(0.55) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var nextLabel: String {
        guard let next else { return "No prayer times yet" }
        let tomorrow = !Calendar.current.isDate(next.date, inSameDayAs: now)
        let prefix = tomorrow ? "\(next.prayer.name) tomorrow" : next.prayer.name
        return "\(prefix) in \(countdown(to: next.date))"
    }

    private func countdown(to date: Date) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        let minutes = Int(remaining / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 { return "\(hours)h \(rest)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "a moment"
    }

    private func timeText(_ date: Date) -> String {
        prayerTimeFormatter.timeZone = .current
        return prayerTimeFormatter.string(from: date)
    }

    // MARK: - Location message

    private func message(icon: String, title: String, subtitle: String, button: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if let button {
                Button {
                    locationDenied ? onOpenSettings() : onRetry()
                } label: {
                    Text(button)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
