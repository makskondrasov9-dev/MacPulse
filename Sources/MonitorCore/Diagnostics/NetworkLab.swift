import Darwin
import Foundation
import SystemConfiguration

public struct TraceHop: Identifiable, Equatable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let address: String?
    public let milliseconds: [Double]
    public let timedOut: Bool
    public static func parse(_ line: String) -> Self? {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first, let number = Int(first), (1...64).contains(number) else { return nil }
        let address = parts.dropFirst().first { NetworkDiagnosticsService.validIP($0.trimmingCharacters(in: CharacterSet(charactersIn: "()"))) }
        var times: [Double] = []
        for i in 1..<parts.count where parts[i] == "ms" {
            if let value = Double(parts[i - 1]), value.isFinite, value >= 0 { times.append(value) }
        }
        guard address != nil || parts.contains("*") else { return nil }
        return Self(number: number, address: address?.trimmingCharacters(in: CharacterSet(charactersIn: "()")), milliseconds: times, timedOut: times.isEmpty)
    }
}

public struct IPv6Report: Sendable {
    public let addresses: [String]
    public let interface: String?
    public let gateway: String?
    /// nil: no gateway or no conclusive response. A missing ICMP reply isn't proof of no IPv6.
    public let gatewayResponded: Bool?
}

public enum NetworkLab {
    public static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else { return false }
        if NetworkDiagnosticsService.validIP(host) { return true }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
    }
    public static func trace(host: String, hop: @Sendable (TraceHop) async -> Void) async throws {
        guard validHost(host) else { throw DiagnosticError.failed("Invalid traceroute host") }
        let ipv6 = host.contains(":")
        let result = try await DiagnosticProcess.run(ipv6 ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute",
            arguments: ["-n", "-m", "20", "-q", "1", "-w", "1", host], timeout: 35) { line in
                if let value = TraceHop.parse(line) { await hop(value) }
            }
        guard result.status == 0 else { throw DiagnosticError.failed("Traceroute did not complete") }
    }
    static func ipv6Addresses(_ interfaces: [NetworkIdentity], primary: String?) -> [String] {
        guard let primary else { return [] }
        return interfaces.filter { $0.interface == primary }.flatMap(\.addresses).filter { $0.contains(":") }
    }
    public static func ipv6() async throws -> IPv6Report {
        let interfaces = NetworkIdentity.current()
        let state = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv6" as CFString) as? [String: Any]
        let interface = state?["PrimaryInterface"] as? String ?? interfaces.first(where: { $0.isPrimary == true })?.interface
        let gateway = state?["Router"] as? String
        let addresses = ipv6Addresses(interfaces, primary: interface)
        guard let gateway, let interface, !interface.isEmpty,
              interface.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
              NetworkDiagnosticsService.validIP(String(gateway.split(separator: "%").first ?? "")) else {
            return IPv6Report(addresses: addresses, interface: interface, gateway: nil, gatewayResponded: nil)
        }
        let target = gateway.contains("%") ? gateway : (gateway.lowercased().hasPrefix("fe80:") ? gateway + "%" + interface : gateway)
        do {
            let result = try await DiagnosticProcess.run("/sbin/ping6", arguments: ["-n", "-c", "1", target], timeout: 5)
            return IPv6Report(addresses: addresses, interface: interface, gateway: target, gatewayResponded: result.status == 0)
        } catch is CancellationError { throw CancellationError() }
        catch { return IPv6Report(addresses: addresses, interface: interface, gateway: target, gatewayResponded: nil) }
    }
}

public struct PublicIPConfiguration: Equatable, Sendable {
    public static let defaultURL = "https://api.ipify.org"
    public let url: URL
    public let interval: TimeInterval
    public init(endpoint: String, interval: TimeInterval) throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw DiagnosticError.failed("Use an HTTPS URL without credentials or a fragment")
        }
        guard interval.isFinite, (15...3600).contains(interval) else { throw DiagnosticError.failed("IP interval must be between 15 and 3600 seconds") }
        self.url = url; self.interval = interval
    }
    public static func parse(_ data: Data) throws -> String {
        guard data.count <= 1024 else { throw DiagnosticError.failed("Public IP response exceeded limit") }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let ip = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["ip"] ?? text
        guard NetworkDiagnosticsService.validIP(ip) else { throw DiagnosticError.failed("Public IP is unavailable") }
        return ip
    }
}
