import SwiftUI

struct MonitorPage: View {
    @StateObject private var monitor = SystemMonitor()

    var body: some View {
        MonitorPageContent(snapshot: monitor.snapshot)
            .onAppear { monitor.start() }
            .onDisappear { monitor.stop() }
    }
}

struct MonitorPageContent: View {
    let snapshot: MonitorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("MONITOR")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.38))
                Spacer()
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 3, height: 3)
                Text("LIVE")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.24))
            }

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 0) {
                metric("CPU", percent(snapshot.cpuPercent))
                metric("GPU", snapshot.gpuPercent.map(percent) ?? "—")
                metric("RAM", percent(snapshot.ramPercent))
                network
                metric("DSK", percent(snapshot.diskPercent))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 3) {
            speedLine("arrow.down", formatTransferRate(snapshot.downloadBytesPerSecond))
            speedLine("arrow.up", formatTransferRate(snapshot.uploadBytesPerSecond))
        }
        .frame(maxWidth: .infinity)
    }

    private func speedLine(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
