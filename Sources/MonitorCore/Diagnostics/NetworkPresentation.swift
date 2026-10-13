import Darwin
import Foundation

/// A tunnel interface is evidence of a tunnel, not proof of VPN traffic protection.
public struct NetworkPresentation: Sendable {
    public let interfaces: [NetworkIdentity]
    public init(_ interfaces: [NetworkIdentity]) { self.interfaces = interfaces }

    public static func isTunnel(_ name: String) -> Bool { name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") }
    public static func isUsableAddress(_ address: String) -> Bool {
        let value = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        var ipv4 = in_addr(), ipv6 = in6_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            let bytes = withUnsafeBytes(of: &ipv4) { Array($0) }
            return bytes[0] != 0 && bytes[0] != 127 && bytes[0] < 224 && !(bytes[0] == 169 && bytes[1] == 254)
        }
        if inet_pton(AF_INET6, value, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            return !bytes.allSatisfy { $0 == 0 } && !(bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1)
                && bytes[0] != 255 && !(bytes[0] == 254 && bytes[1] & 0xc0 == 0x80)
        }
        return false
    }
    public func visibleInterfaces(details: Bool) -> [NetworkIdentity] {
        if details { return interfaces }
        return interfaces.compactMap { interface in
            var visible = interface
            visible.addresses = interface.addresses.filter(Self.isUsableAddress)
            return visible.addresses.isEmpty ? nil : visible
        }
    }
    private func preferredAddress(_ interfaces: [NetworkIdentity]) -> String? {
        let ordered = interfaces.sorted {
            if ($0.isPrimary ?? false) != ($1.isPrimary ?? false) { return $0.isPrimary == true }
            return $0.interface < $1.interface
        }
        for interface in ordered {
            let addresses = interface.addresses.filter(Self.isUsableAddress)
            if let ipv4 = addresses.first(where: { !$0.contains(":") }) { return ipv4 }
            if let ipv6 = addresses.first { return ipv6 }
        }
        return nil
    }
    public var localIP: String? { preferredAddress(interfaces.filter { !Self.isTunnel($0.interface) }) }
    public var tunnelIP: String? { preferredAddress(interfaces.filter { Self.isTunnel($0.interface) }) }
    public var hasTunnel: Bool { tunnelIP != nil }
    public func menuIP(source: String, publicIP: String?) -> String? { source == "public" ? publicIP : localIP }
}
