import Darwin
import Foundation

public struct HardwareProfile: Sendable {
    public let processor: String
    public let isAppleSilicon: Bool
    public static let current: HardwareProfile = {
        #if arch(arm64)
        let silicon = true
        #else
        let silicon = false
        #endif
        var size = 0
        let key = "machdep.cpu.brand_string"
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else {
            return HardwareProfile(processor: silicon ? "Apple Silicon" : "Intel", isAppleSilicon: silicon)
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else {
            return HardwareProfile(processor: silicon ? "Apple Silicon" : "Intel", isAppleSilicon: silicon)
        }
        return HardwareProfile(processor: String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self), isAppleSilicon: silicon)
    }()

    static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Нормальное"
        case .fair: "Повышенное"
        case .serious: "Высокое"
        case .critical: "Критическое"
        @unknown default: "Неизвестно"
        }
    }
}
