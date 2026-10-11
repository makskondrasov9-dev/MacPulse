import Foundation

public struct InstalledApplication: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let architecture: String
}

public struct UninstallerItem: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let bytes: UInt64
    public let isApplication: Bool
    /// A name match is only a suggestion, never a default deletion selection.
    public let nameMatch: Bool
}

public struct UninstallerPreview: Sendable {
    public let id: UUID
    public let application: InstalledApplication
    public let items: [UninstallerItem]
    public let issues: [String]
    public var bytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
}

public struct UninstallerResult: Sendable {
    public var removedItems = 0
    public var removedBytes: UInt64 = 0
    public var issues: [String] = []
}

public enum UninstallerError: Error, LocalizedError {
    case protectedApp, invalidApp, running, stale, busy, sharedData
    public var errorDescription: String? {
        switch self {
        case .protectedApp: L("Это приложение защищено от удаления.")
        case .invalidApp: L("Выберите обычный файл .app с корректным Bundle ID. Симлинки не поддерживаются.")
        case .running: L("Сначала завершите приложение и его фоновые процессы, затем повторите сканирование.")
        case .stale: L("Файлы изменились после сканирования. Повторите сканирование.")
        case .busy: L("Дождитесь завершения текущей операции.")
        case .sharedData: L("Найдена другая копия приложения: общие данные не выбраны для удаления.")
        }
    }
}

/// Read only the Mach-O header; never load or execute the selected application.
enum ApplicationArchitecture {
    static func read(_ executable: URL) -> String {
        guard let file = try? FileHandle(forReadingFrom: executable) else { return "—" }
        defer { try? file.close() }
        return decode((try? file.read(upToCount: 4096)) ?? Data())
    }
    static func decode(_ data: Data) -> String {
        let bytes = Array(data)
        func word(_ offset: Int, little: Bool) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * (little ? $1 : 3 - $1)) }
        }
        guard let magic = word(0, little: false) else { return "—" }
        var cpus: Set<UInt32> = []
        if [UInt32(0xcafebabe), 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic) {
            let little = magic == 0xbebafeca || magic == 0xbfbafeca
            let stride = magic == 0xcafebabf || magic == 0xbfbafeca ? 32 : 20
            guard let count = word(4, little: little), count > 0, count <= 32,
                  8 + Int(count) * stride <= bytes.count else { return "—" }
            for i in 0..<Int(count) { if let cpu = word(8 + i * stride, little: little) { cpus.insert(cpu) } }
        } else if [UInt32(0xfeedfacf), 0xcffaedfe, 0xfeedface, 0xcefaedfe].contains(magic),
                  let cpu = word(4, little: magic == 0xcffaedfe || magic == 0xcefaedfe) { cpus.insert(cpu) }
        let intel = cpus.contains(0x01000007), arm = cpus.contains(0x0100000c)
        if intel && arm { return "Universal" }
        if intel { return "Intel" }
        if arm { return "Apple Silicon" }
        return "—"
    }
}
