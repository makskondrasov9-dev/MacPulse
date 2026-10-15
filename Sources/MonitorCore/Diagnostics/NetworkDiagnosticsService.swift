import Darwin
import Foundation
import SystemConfiguration

public struct NetworkQualityResult: Sendable {
    public let downloadMbps: Double?
    public let uploadMbps: Double?
    public let latencyMilliseconds: Double?
    public let responsiveness: Double?

    public static func parse(_ data: Data) throws -> Self {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiagnosticError.failed("Invalid networkQuality response")
        }
        func number(_ key: String) -> Double? {
            guard let n = json[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let value = n.doubleValue
            return value.isFinite && value >= 0 ? value : nil
        }
        let download = number("dl_throughput").map { $0 / 1_000_000 }
        let upload = number("ul_throughput").map { $0 / 1_000_000 }
        guard download != nil || upload != nil else { throw DiagnosticError.failed("No network throughput results") }
        return Self(downloadMbps: download, uploadMbps: upload, latencyMilliseconds: number("base_rtt") ?? number("base_rtt_mean") ?? number("idle_latency"),
                    responsiveness: number("responsiveness") ?? number("rpm"))
    }
}

public actor NetworkDiagnosticsService {
    private var measuring = false
    public init() {}

    public func measure(executable: URL = URL(fileURLWithPath: "/usr/bin/networkQuality"),
                        arguments: [String] = ["-c"], timeout: TimeInterval = 120,
                        targets: @Sendable ([String]) async -> Void = { _ in }) async throws -> NetworkQualityResult {
        guard !measuring else { throw DiagnosticError.failed("Network test already running") }
        measuring = true
        defer { measuring = false }
        var args = arguments
        var configFile: URL?
        defer { if let configFile { try? FileManager.default.removeItem(at: configFile) } }
        if executable.path == "/usr/bin/networkQuality", arguments == ["-c"] {
            let configURL = URL(string: "https://mensura.cdn-apple.com/api/v1/gm/config")!
            await targets([configURL.absoluteString])
            let data = try await DiagnosticHTTP.fetch(configURL, maximumBytes: 65_536)
            let endpoints = try NetworkTestConfiguration.endpoints(data)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-network-config-\(UUID().uuidString).json")
            try data.write(to: path, options: [.atomic])
            configFile = path
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            args += ["-C", path.absoluteString]
            await targets(endpoints)
        }
        let result = try await DiagnosticProcess.run(executable.path, arguments: args, timeout: timeout)
        guard result.status == 0 else { throw DiagnosticError.failed("networkQuality failed (\(result.status))") }
        return try NetworkQualityResult.parse(result.data)
    }

    public func publicIP(endpoint: String = PublicIPConfiguration.defaultURL) async throws -> String {
        let config = try PublicIPConfiguration(endpoint: endpoint, interval: 60)
        return try PublicIPConfiguration.parse(await DiagnosticHTTP.fetch(config.url, maximumBytes: 1024))
    }

    public static func validIP(_ value: String) -> Bool {
        var ipv4 = in_addr(), ipv6 = in6_addr()
        return inet_pton(AF_INET, value, &ipv4) == 1 || inet_pton(AF_INET6, value, &ipv6) == 1
    }
}

public struct NetworkIdentity: Codable, Equatable, Sendable {
    public var interface: String
    public var addresses: [String]
    public var mac: String?
    public var label: String?
    public var isPrimary: Bool? = nil
    public init(interface: String, addresses: [String], mac: String? = nil, label: String? = nil) {
        self.interface = interface; self.addresses = addresses.sorted(); self.mac = mac; self.label = label
    }
    public static func current() -> [Self] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        let physical = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        var macs: [String: String] = [:]
        var labels: [String: String] = [:]
        for interface in physical {
            if let name = SCNetworkInterfaceGetBSDName(interface) as String? {
                let type = SCNetworkInterfaceGetInterfaceType(interface)
                labels[name] = type == kSCNetworkInterfaceTypeIEEE80211 ? "Wi-Fi" : (type == kSCNetworkInterfaceTypeEthernet ? "Ethernet" : name)
            }
            if let name = SCNetworkInterfaceGetBSDName(interface) as String?,
               let mac = SCNetworkInterfaceGetHardwareAddressString(interface) as String? { macs[name] = mac }
        }
        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let global6 = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv6" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String ?? global6?["PrimaryInterface"] as? String
        var addresses: [String: [String]] = [:]
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let row = entry.pointee
            if let link = row.ifa_addr, Int32(link.pointee.sa_family) == AF_LINK {
                let dl = UnsafeRawPointer(link).assumingMemoryBound(to: sockaddr_dl.self).pointee
                let offset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)! + Int(dl.sdl_nlen)
                if dl.sdl_alen == 6 && offset + 6 <= Int(dl.sdl_len) {
                    let bytes = UnsafeRawPointer(link).advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                    macs[String(cString: row.ifa_name)] = (0..<6).map { String(format: "%02x", bytes[$0]) }.joined(separator: ":")
                }
            }
            guard row.ifa_flags & UInt32(IFF_UP) != 0, row.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = row.ifa_addr, [AF_INET, AF_INET6].contains(Int32(address.pointee.sa_family)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: row.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("bridge") else { continue }
            addresses[name, default: []].append(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return addresses.map { name, values in
            var identity = Self(interface: name, addresses: values, mac: macs[name], label: labels[name])
            identity.isPrimary = name == primary
            return identity
        }.sorted { $0.interface < $1.interface }
    }
}

public struct IPHistoryEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let date: Date
    public let interfaces: [NetworkIdentity]
    public let publicIP: String?
}

public struct IPHistory: Codable, Sendable {
    public private(set) var entries: [IPHistoryEntry] = []
    public init() {}
    public mutating func record(interfaces: [NetworkIdentity], publicIP: String?, at date: Date = Date()) {
        // MAC is metadata, not an IP-change trigger. Never reuse a stale public address after a network change.
        let normalized = interfaces.sorted { $0.interface < $1.interface }
        if let last = entries.last, last.interfaces.map({ ($0.interface, $0.addresses) }).elementsEqual(normalized.map { ($0.interface, $0.addresses) }, by: { $0.0 == $1.0 && $0.1 == $1.1 }), last.publicIP == publicIP { return }
        entries.append(IPHistoryEntry(date: date, interfaces: normalized, publicIP: publicIP))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
}
