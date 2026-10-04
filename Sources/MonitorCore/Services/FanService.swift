import CSystem
import Darwin
import Foundation
import IOKit

public struct FanReading: Codable, Sendable, Identifiable {
    public let id: Int
    public let rpm: Double
    public let minimum: Double
    public let maximum: Double
    public let controllable: Bool
    public let issue: String?
}

public struct FanSnapshot: Codable, Sendable {
    public let fans: [FanReading]
    public let issue: String?
}

public enum FanError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): message } }
}

struct FanValue {
    let type: UInt32
    let bytes: [UInt8]
}

enum FanCodec {
    static func decode(_ value: FanValue) throws -> Double {
        let bytes = value.bytes
        let result: Double
        switch value.type {
        case try SMCDecoder.fourCC("fpe2"):
            guard bytes.count == 2 else { throw SMCError.invalidPayload }
            result = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case try SMCDecoder.fourCC("flt "):
            guard bytes.count == 4 else { throw SMCError.invalidPayload }
            result = Double(Float(bitPattern: bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }))
        case try SMCDecoder.fourCC("ui8 "), try SMCDecoder.fourCC("ui16"):
            guard (1...2).contains(bytes.count) else { throw SMCError.invalidPayload }
            result = Double(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        default: throw SMCError.unsupportedType
        }
        guard result.isFinite, (0...20000).contains(result) else { throw SMCError.invalidPayload }
        return result
    }

    static func encodeRPM(_ rpm: Double, type: UInt32) throws -> [UInt8] {
        guard rpm.isFinite, (0...16000).contains(rpm) else { throw SMCError.invalidPayload }
        switch type {
        case try SMCDecoder.fourCC("fpe2"):
            let bits = UInt16((rpm * 4).rounded())
            return [UInt8(bits >> 8), UInt8(bits & 255)]
        case try SMCDecoder.fourCC("flt "):
            let bits = Float(rpm).bitPattern
            return (0..<4).map { UInt8((bits >> ($0 * 8)) & 255) }
        default: throw SMCError.unsupportedType
        }
    }
}

/// Separate connection from the temperature collector. Only FnMn can be written;
/// firmware automatic control remains enabled and may raise RPM above our floor.
final class FanDevice {
    private var connection: io_connect_t = 0
    deinit { if connection != 0 { IOServiceClose(connection) } }

    private func call(_ input: MonitorSMCMessage) throws -> MonitorSMCMessage {
        if connection == 0 {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard service != 0 else { throw SMCError.unavailable }
            defer { IOObjectRelease(service) }
            let status = IOServiceOpen(service, MonitorTaskSelf(), 0, &connection)
            guard status == KERN_SUCCESS else { throw SMCError.kernel(status) }
        }
        var request = input, output = MonitorSMCMessage()
        var size = MemoryLayout<MonitorSMCMessage>.size
        let status = IOConnectCallStructMethod(connection, 2, &request, size, &output, &size)
        guard status == KERN_SUCCESS else {
            IOServiceClose(connection); connection = 0
            throw SMCError.kernel(status)
        }
        guard size == MemoryLayout<MonitorSMCMessage>.size else { throw SMCError.invalidPayload }
        guard output.result == 0 else { throw SMCError.controller(output.result) }
        return output
    }

    func read(_ key: String) throws -> FanValue {
        var request = MonitorSMCMessage()
        request.key = try SMCDecoder.fourCC(key)
        request.command = 9
        let info = try call(request).keyInfo
        guard (1...32).contains(info.dataSize) else { throw SMCError.invalidPayload }
        request.command = 5
        request.keyInfo.dataSize = info.dataSize
        var response = try call(request)
        return FanValue(type: info.dataType, bytes: withUnsafeBytes(of: &response.bytes) { Array($0.prefix(Int(info.dataSize))) })
    }

    func speed(_ key: String) throws -> Double { try FanCodec.decode(read(key)) }

    func snapshot() -> FanSnapshot {
        do {
            let count = try speed("FNum")
            guard count.rounded() == count, (0...10).contains(count) else { throw SMCError.invalidPayload }
            let fans = (0..<Int(count)).compactMap { id -> FanReading? in
                guard let current = try? speed("F\(id)Ac") else { return nil }
                let minimum = (try? speed("F\(id)Mn")) ?? 0
                let maximum = (try? speed("F\(id)Mx")) ?? 0
                #if arch(x86_64)
                let supported = minimum > 0 && maximum > minimum && maximum <= 16000
                #else
                // Apple Silicon fan RPM is readable on some models, but writing
                // Intel minimum keys there has not been validated.
                let supported = false
                #endif
                return FanReading(id: id, rpm: current, minimum: minimum, maximum: maximum,
                    controllable: supported, issue: supported ? nil : "Управление этой моделью не поддерживается; доступны показания.")
            }
            return FanSnapshot(fans: fans, issue: nil)
        } catch { return FanSnapshot(fans: [], issue: String(describing: error)) }
    }

    func writeMinimum(id: Int, rpm: Double) throws {
        #if !arch(x86_64)
        throw FanError.message("Управление вентиляторами Apple Silicon пока не поддерживается.")
        #else
        guard (0..<10).contains(id) else { throw SMCError.invalidKey }
        let key = "F\(id)Mn"
        let value = try read(key)
        let bytes = try FanCodec.encodeRPM(rpm, type: value.type)
        guard bytes.count == value.bytes.count else { throw SMCError.invalidPayload }
        var request = MonitorSMCMessage()
        request.key = try SMCDecoder.fourCC(key)
        request.command = 6
        request.keyInfo.dataSize = UInt32(bytes.count)
        withUnsafeMutableBytes(of: &request.bytes) { $0.copyBytes(from: bytes) }
        _ = try call(request)
        guard abs(try speed(key) - rpm) < 1 else { throw FanError.message("SMC не подтвердил новые обороты.") }
        #endif
    }

    func automaticMode(id: Int) -> Bool {
        let flags = try? speed("FS! ")
        let mode = try? speed("F\(id)Md")
        if let flags, Int(flags) & (1 << id) != 0 { return false }
        if let mode, mode != 0 { return false }
        return flags != nil || mode != nil
    }

}

public actor FanService {
    private let device = FanDevice()
    public init() {}
    public func sample() -> FanSnapshot { device.snapshot() }
}
