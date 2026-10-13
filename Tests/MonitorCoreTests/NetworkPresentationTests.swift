import Testing
@testable import MonitorCore

struct NetworkPresentationTests {
    @Test func systemTunnelsAreNotReportedAsVPN() {
        let interfaces = (0..<4).map { NetworkIdentity(interface: "utun\($0)", addresses: ["fe80::1%utun\($0)"]) }
        let presentation = NetworkPresentation(interfaces)
        #expect(!presentation.hasTunnel)
        #expect(presentation.visibleInterfaces(details: false).isEmpty)
        #expect(presentation.visibleInterfaces(details: true).count == 4)
    }
    @Test func assignedTunnelAndPhysicalIPRemainSeparate() {
        let presentation = NetworkPresentation([
            NetworkIdentity(interface: "en0", addresses: ["192.168.31.173", "fe80::1%en0"]),
            NetworkIdentity(interface: "utun4", addresses: ["10.9.9.8", "fd58::1", "fe80::1%utun4"])
        ])
        #expect(presentation.localIP == "192.168.31.173")
        #expect(presentation.tunnelIP == "10.9.9.8")
        #expect(presentation.hasTunnel)
        #expect(presentation.visibleInterfaces(details: false)[1].addresses.count == 2)
        #expect(presentation.menuIP(source: "public", publicIP: nil) == nil)
        #expect(presentation.menuIP(source: "public", publicIP: "203.0.113.2") == "203.0.113.2")
        #expect(presentation.menuIP(source: "local", publicIP: "203.0.113.2") == "192.168.31.173")
    }
    @Test func primaryInterfaceAndIPv6OnlyNetworks() {
        var wifi = NetworkIdentity(interface: "en1", addresses: ["2001:db8::123"])
        wifi.isPrimary = true
        let presentation = NetworkPresentation([NetworkIdentity(interface: "en0", addresses: ["192.0.2.1"]), wifi])
        #expect(presentation.localIP == "2001:db8::123")
        #expect(NetworkPresentation([NetworkIdentity(interface: "utun0", addresses: ["fd58::1"])]).hasTunnel)
    }
    @Test func unusableAddressesAreFiltered() {
        for value in ["", "bad", "::", "::1", "fe80::1%en0", "febf::1", "ff02::1", "127.0.0.1", "169.254.1.1", "0.0.0.0", "224.0.0.1"] {
            #expect(!NetworkPresentation.isUsableAddress(value))
        }
        for value in ["10.0.0.1", "192.168.1.1", "2001:db8::1", "fd58::1"] {
            #expect(NetworkPresentation.isUsableAddress(value))
        }
    }
}
