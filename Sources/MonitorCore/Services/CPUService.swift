import CSystem
import Darwin
import Foundation

struct CPUService {
    private var previous: [[UInt32]]?

    mutating func sample() -> CPUMetrics? {
        let host = mach_host_self()
        defer { mach_port_deallocate(MonitorTaskSelf(), host) }
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &count) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(MonitorTaskSelf(), vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let width = Int(CPU_STATE_MAX)
        guard Int(count) >= Int(processorCount) * width else { return nil }
        let current = (0..<Int(processorCount)).map { core in
            (0..<width).map { UInt32(bitPattern: info[core * width + $0]) }
        }
        defer { previous = current }
        guard let previous, previous.count == current.count else { return CPUMetrics(usage: nil, cores: []) }
        var busySum = 0.0
        var totalSum = 0.0
        let cores = zip(current, previous).map { now, old -> Double in
            let delta = zip(now, old).map { Double($0 &- $1) }
            let total = delta.reduce(0, +)
            let busy = total - delta[Int(CPU_STATE_IDLE)]
            busySum += busy
            totalSum += total
            return total > 0 ? busy / total * 100 : 0
        }
        return CPUMetrics(usage: totalSum > 0 ? busySum / totalSum * 100 : nil, cores: cores)
    }

    static func uptime() -> TimeInterval? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return nil }
        return max(0, Date().timeIntervalSince1970 - Double(boot.tv_sec) - Double(boot.tv_usec) / 1_000_000)
    }
}
