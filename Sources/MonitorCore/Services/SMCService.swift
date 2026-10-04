import CSystem
import Foundation
import IOKit

public struct TemperatureReading: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let celsius: Double?
    public let issue: String?
}

enum SMCError: Error, CustomStringConvertible {
    case unavailable, invalidKey, invalidPayload, unsupportedType
    case kernel(kern_return_t), controller(UInt8)
    case implausibleTemperature(Double)

    var description: String {
        switch self {
        case .unavailable: "AppleSMC недоступен"
        case .invalidKey: "Некорректный ключ SMC"
        case .invalidPayload: "Некорректные данные SMC"
        case .unsupportedType: "Неподдерживаемый формат температуры"
        case .kernel(let code): "Ошибка IOKit: \(code)"
        case .controller(let code): "Ответ SMC: \(code)"
        case .implausibleTemperature(let value): "Сомнительное показание: \(String(format: "%.2f", value)) °C"
        }
    }
}

enum SMCDecoder {
    static func fourCC(_ string: String) throws -> UInt32 {
        let bytes = Array(string.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else { throw SMCError.invalidKey }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func temperature(type: UInt32, bytes: [UInt8]) throws -> Double {
        let value: Double
        switch type {
        case try fourCC("sp78"):
            guard bytes.count == 2 else { throw SMCError.invalidPayload }
            let bits = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            value = Double(Int16(bitPattern: bits)) / 256
        case try fourCC("flt "):
            guard bytes.count == 4 else { throw SMCError.invalidPayload }
            // Intel SMC floating point payloads use little-endian IEEE 754.
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            value = Double(Float(bitPattern: bits))
        default: throw SMCError.unsupportedType
        }
        guard value.isFinite, (-40...150).contains(value) else { throw SMCError.invalidPayload }
        return value
    }
}

/// All driver access is serialized by this actor; no write commands are exposed.
public actor SMCService {
    public static let keys = ["TC0D", "TC0P", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C",
                              "TG0D", "TG0P", "TH0P", "TA0P"]
    private var connection: io_connect_t = 0
    private var metadata: [String: MonitorSMCKeyInfo] = [:]
    private var failures: [String: (retry: Date, message: String)] = [:]
    private var nextOpenAttempt = Date.distantPast
    private var openIssue = "AppleSMC недоступен"

    public init() {}

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func close() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
        metadata.removeAll()
        failures.removeAll()
        nextOpenAttempt = .distantPast
    }

    public func sample() -> [TemperatureReading] {
        #if !arch(x86_64)
        return []
        #else
        do { try openIfNeeded() }
        catch {
            return Self.keys.map { TemperatureReading(key: $0, celsius: nil, issue: String(describing: error)) }
        }
        return Self.keys.map { key in
            guard connection != 0 else {
                return TemperatureReading(key: key, celsius: nil, issue: openIssue)
            }
            if let failed = failures[key], failed.retry > Date() {
                return TemperatureReading(key: key, celsius: nil, issue: failed.message)
            }
            do {
                let value = try readTemperature(key)
                failures[key] = nil
                return TemperatureReading(key: key, celsius: value, issue: nil)
            } catch {
                let message = String(describing: error)
                // Missing OCLP keys are retried slowly rather than every UI update.
                failures[key] = (Date().addingTimeInterval(60), message)
                metadata[key] = nil
                return TemperatureReading(key: key, celsius: nil, issue: message)
            }
        }
        #endif
    }

    private func openIfNeeded() throws {
        guard connection == 0 else { return }
        guard Date() >= nextOpenAttempt else { throw SMCOpenFailure(message: openIssue) }
        nextOpenAttempt = Date().addingTimeInterval(60)
        do {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard service != 0 else { throw SMCError.unavailable }
            defer { IOObjectRelease(service) }
            var handle: io_connect_t = 0
            let status = IOServiceOpen(service, MonitorTaskSelf(), 0, &handle)
            guard status == KERN_SUCCESS else { throw SMCError.kernel(status) }
            connection = handle
        } catch {
            openIssue = String(describing: error)
            throw error
        }
    }

    private func call(_ request: MonitorSMCMessage) throws -> MonitorSMCMessage {
        var input = request
        var output = MonitorSMCMessage()
        var size = MemoryLayout<MonitorSMCMessage>.size
        let status = IOConnectCallStructMethod(connection, 2, &input, size, &output, &size)
        guard status == KERN_SUCCESS else {
            // A driver restart or sleep/wake can invalidate a user-client port.
            close()
            nextOpenAttempt = Date().addingTimeInterval(60)
            openIssue = SMCError.kernel(status).description
            throw SMCError.kernel(status)
        }
        guard size == MemoryLayout<MonitorSMCMessage>.size else { throw SMCError.invalidPayload }
        guard output.result == 0 else { throw SMCError.controller(output.result) }
        return output
    }

    private func readTemperature(_ key: String) throws -> Double {
        var request = MonitorSMCMessage()
        request.key = try SMCDecoder.fourCC(key)
        let info: MonitorSMCKeyInfo
        if let cached = metadata[key] { info = cached }
        else {
            request.command = 9 // Read key metadata.
            info = try call(request).keyInfo
            guard (1...32).contains(info.dataSize) else { throw SMCError.invalidPayload }
            metadata[key] = info
        }
        request.command = 5 // Read bytes; never write to SMC.
        request.keyInfo.dataSize = info.dataSize
        var response = try call(request)
        let bytes = withUnsafeBytes(of: &response.bytes) { Array($0.prefix(Int(info.dataSize))) }
        let value = try SMCDecoder.temperature(type: info.dataType, bytes: bytes)
        // This indoor desktop's disconnected/OCLP sensors can fluctuate around
        // zero (TH0P / TC0E). Keep the raw value in diagnostics, not the gauges.
        // The lower bound assumes operation within the iMac's 10°C+ environment.
        guard value >= 10 else { throw SMCError.implausibleTemperature(value) }
        return value
    }
}

private struct SMCOpenFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
