import CSystem
import Testing
@testable import MonitorCore

struct SMCDecoderTests {
    @Test func driverABI() {
        #expect(MemoryLayout<MonitorSMCMessage>.size == 80)
        #expect(MemoryLayout<MonitorSMCMessage>.offset(of: \.bytes) == 48)
    }

    @Test func fourCCUsesProtocolByteOrder() throws {
        #expect(try SMCDecoder.fourCC("TC0D") == 0x54433044)
        #expect(throws: (any Error).self) { try SMCDecoder.fourCC("TC0") }
        #expect(throws: (any Error).self) { try SMCDecoder.fourCC("аб") }
    }

    @Test func signedFixedPointTemperature() throws {
        let type = try SMCDecoder.fourCC("sp78")
        #expect(try SMCDecoder.temperature(type: type, bytes: [0x32, 0x80]) == 50.5)
        #expect(try SMCDecoder.temperature(type: type, bytes: [0xff, 0x80]) == -0.5)
        #expect(try SMCDecoder.temperature(type: type, bytes: [0, 0]) == 0)
    }

    @Test func littleEndianFloatTemperature() throws {
        #expect(try SMCDecoder.temperature(type: SMCDecoder.fourCC("flt "), bytes: [0, 0, 0x48, 0x42]) == 50)
    }

    @Test func rejectsMalformedAndUnsupportedValues() throws {
        let fixed = try SMCDecoder.fourCC("sp78")
        let float = try SMCDecoder.fourCC("flt ")
        #expect(throws: (any Error).self) { try SMCDecoder.temperature(type: fixed, bytes: []) }
        #expect(throws: (any Error).self) { try SMCDecoder.temperature(type: fixed, bytes: [0x80, 0]) }
        #expect(throws: (any Error).self) { try SMCDecoder.temperature(type: float, bytes: [0, 0, 0x80, 0x7f]) }
        #expect(throws: (any Error).self) { try SMCDecoder.temperature(type: float, bytes: [0, 0, 0xc0, 0x7f]) }
        #expect(throws: (any Error).self) { try SMCDecoder.temperature(type: SMCDecoder.fourCC("ui16"), bytes: [0, 50]) }
    }
}
