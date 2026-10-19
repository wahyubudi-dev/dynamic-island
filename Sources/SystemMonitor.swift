import Foundation
import Darwin
import IOKit

struct MonitorSnapshot: Equatable {
    var cpuPercent: Double = 0
    var gpuPercent: Double?
    var ramPercent: Double = 0
    var downloadBytesPerSecond: Double = 0
    var uploadBytesPerSecond: Double = 0
    var diskPercent: Double = 0
}

/// Samples CPU, GPU, RAM, network throughput and disk usage once per second.
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = MonitorSnapshot()

    private var timer: Timer?
    private var running = false

    private var hasCPUBaseline = false
    private var previousCPUBusy: UInt64 = 0
    private var previousCPUTotal: UInt64 = 0

    private var previousNetUp: UInt64 = 0
    private var previousNetDown: UInt64 = 0
    private var previousNetDate: Date?

    func start() {
        guard !running else { return }
        running = true
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func sample() {
        var next = snapshot
        if let cpu = cpuUsage() { next.cpuPercent = cpu }
        next.gpuPercent = gpuUsage()
        next.ramPercent = ramUsage()
        if let rates = networkRates() {
            next.downloadBytesPerSecond = rates.down
            next.uploadBytesPerSecond = rates.up
        }
        next.diskPercent = diskUsage()
        snapshot = next
    }

    // MARK: - CPU

    private func cpuUsage() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount)) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * states
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            busy += user + system + nice
            total += user + system + idle + nice
        }

        guard hasCPUBaseline, total >= previousCPUTotal, busy >= previousCPUBusy else {
            hasCPUBaseline = true
            previousCPUBusy = busy
            previousCPUTotal = total
            return nil
        }

        let deltaTotal = total - previousCPUTotal
        let deltaBusy = busy - previousCPUBusy
        previousCPUBusy = busy
        previousCPUTotal = total

        guard deltaTotal > 0 else { return nil }
        return min(100, max(0, Double(deltaBusy) / Double(deltaTotal) * 100))
    }

    // MARK: - GPU

    private func gpuUsage() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                let utilization = (property["Device Utilization %"] as? NSNumber)?.doubleValue
                    ?? (property["GPU Utilization %"] as? NSNumber)?.doubleValue
                if let utilization {
                    best = max(best ?? 0, utilization)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best.map { min(100, max(0, $0)) }
    }

    // MARK: - RAM

    private func ramUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.ramPercent }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        // Matches Activity Monitor's "Memory Used": app + wired + compressed,
        // leaving reclaimable inactive/cached pages out.
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(usedPages * pageSize) / Double(total) * 100))
    }

    // MARK: - Network

    private func networkRates() -> (down: Double, up: Double)? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            let relevant = name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("utun")
            if relevant,
               entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data64.self).pointee
                down += stats.ifi_ibytes
                up += stats.ifi_obytes
            }
            pointer = entry.ifa_next
        }

        let now = Date()
        defer {
            previousNetDown = down
            previousNetUp = up
            previousNetDate = now
        }

        guard let previousDate = previousNetDate else { return (0, 0) }
        let interval = now.timeIntervalSince(previousDate)
        guard interval > 0, down >= previousNetDown, up >= previousNetUp else { return (0, 0) }
        return (
            Double(down - previousNetDown) / interval,
            Double(up - previousNetUp) / interval
        )
    }

    // MARK: - Disk

    private func diskUsage() -> Double {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let total = values.volumeTotalCapacity, total > 0 else {
            return snapshot.diskPercent
        }
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        let used = Double(total) - Double(available)
        return min(100, max(0, used / Double(total) * 100))
    }
}

/// Rates are rendered without a "/s" suffix, matching the compact strip.
func formatTransferRate(_ bytesPerSecond: Double) -> String {
    let value = max(0, bytesPerSecond)
    if value < 1_000 {
        return "\(Int(value.rounded()))B"
    }
    let kb = value / 1_000
    if kb < 1_000 {
        return kb >= 100 ? String(format: "%.0fKB", kb) : String(format: "%.1fKB", kb)
    }
    let mb = kb / 1_000
    if mb < 1_000 {
        return mb >= 100 ? String(format: "%.0fMB", mb) : String(format: "%.1fMB", mb)
    }
    return String(format: "%.1fGB", mb / 1_000)
}
