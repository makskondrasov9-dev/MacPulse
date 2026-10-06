import CSystem
import Darwin
import Foundation
import SystemConfiguration

public struct NetworkMetrics: Sendable {
    public var interfaces: [String] = []
    public var downloadBytesPerSecond: Double? = nil
    public var uploadBytesPerSecond: Double? = nil
    public var receivedBytes: UInt64 = 0
    public var sentBytes: UInt64 = 0
    public var isAvailable = false
    public init() {}
}

struct NetworkCounter: Sendable {
    let id: String
    let label: String
    let received: UInt64
    let sent: UInt64
}

/// Keeps a baseline per physical interface. VPN/loopback/AirDrop counters are
/// excluded so tunneled traffic is not counted a second time.
struct NetworkAccumulator {
    private var previous: [String: NetworkCounter] = [:]
    private var previousTime: TimeInterval?
    private var received: UInt64 = 0
    private var sent: UInt64 = 0

    mutating func sample(_ counters: [NetworkCounter]?, at time: TimeInterval) -> NetworkMetrics {
        var result = NetworkMetrics()
        result.receivedBytes = received
        result.sentBytes = sent
        guard let counters, time.isFinite else {
            previous = [:]; previousTime = nil
            return result
        }
        result.isAvailable = true
        result.interfaces = counters.map(\.label).sorted()
        let elapsed = previousTime.map { time - $0 }
        var incoming: UInt64 = 0, outgoing: UInt64 = 0
        if let elapsed, elapsed > 0 {
            for counter in counters {
                guard let old = previous[counter.id] else { continue }
                // Reset/reconnection starts a new baseline, never a negative spike.
                if counter.received >= old.received { incoming += counter.received - old.received }
                if counter.sent >= old.sent { outgoing += counter.sent - old.sent }
            }
            received += incoming; sent += outgoing
            result.downloadBytesPerSecond = Double(incoming) / elapsed
            result.uploadBytesPerSecond = Double(outgoing) / elapsed
        }
        previous = Dictionary(counters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        previousTime = time
        result.receivedBytes = received
        result.sentBytes = sent
        return result
    }
}

/// Used only by MetricCollector's actor, in the existing polling loop.
public struct NetworkMonitorService {
    private var accumulator = NetworkAccumulator()
    private var interfaceLabels: [String: String] = [:]
    private var labelsUpdated = -Double.infinity
    public init() {}

    public mutating func sample() -> NetworkMetrics {
        let time = ProcessInfo.processInfo.systemUptime
        if time - labelsUpdated >= 30 {
            interfaceLabels = Self.physicalInterfaces()
            labelsUpdated = time
        }
        var pointer: UnsafeMutablePointer<MonitorNetworkCounter>?
        var count = 0
        guard MonitorCopyNetworkCounters(&pointer, &count) == 0 else {
            return accumulator.sample(nil, at: time)
        }
        defer { free(pointer) }
        let rows = UnsafeBufferPointer(start: pointer, count: count)
        var refreshed = false
        let counters: [NetworkCounter] = rows.compactMap { row in
            var name = row.name
            let bsdName = withUnsafePointer(to: &name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
            }
            // Pick up newly attached Ethernet adapters without waiting 30 seconds.
            if interfaceLabels[bsdName] == nil && bsdName.hasPrefix("en") && !refreshed {
                interfaceLabels = Self.physicalInterfaces()
                labelsUpdated = time
                refreshed = true
            }
            guard let label = interfaceLabels[bsdName] else { return nil }
            return NetworkCounter(id: "\(bsdName):\(row.index)", label: "\(label) (\(bsdName))",
                                  received: row.received, sent: row.sent)
        }
        return accumulator.sample(counters, at: time)
    }

    private static func physicalInterfaces() -> [String: String] {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        var result: [String: String] = [:]
        for interface in interfaces {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) else { continue }
            // en* includes internal and USB/Thunderbolt Ethernet as well as Wi-Fi.
            guard name.hasPrefix("en") else { continue }
            if type == kSCNetworkInterfaceTypeIEEE80211 { result[name] = "Wi-Fi" }
            else if type == kSCNetworkInterfaceTypeEthernet { result[name] = "Ethernet" }
        }
        return result
    }
}
