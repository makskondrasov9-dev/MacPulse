import Foundation

public enum CleanerCategory: String, CaseIterable, Sendable, Identifiable {
    case video = "Видео и 3D", audio = "Музыка и DAW", games = "Игры и шейдеры"
    case development = "Разработка", media = "Мессенджеры и медиа", browsers = "Браузеры"
    case system = "Логи и Корзина", orphaned = "Возможные остатки программ"
    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .games: "gamecontroller"
        case .development: "hammer"
        case .media: "message"
        case .browsers: "globe"
        case .system: "trash"
        case .orphaned: "questionmark.folder"
        }
    }
}

public struct CleanerItem: Identifiable, Sendable {
    public let id: UUID
    public let category: CleanerCategory
    public let name: String
    public let path: String
    public let bytes: UInt64
    public let fileCount: Int
    public let sensitive: Bool
    public let canDelete: Bool
    public let note: String?
    public let issues: [String]
}

public struct CleanerScan: Sendable {
    public let id: UUID
    public let items: [CleanerItem]
    public let deepBrowsers: Bool
    public let issues: [String]
    public var bytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
}

public struct CleanerProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
}

public struct CleanerResult: Sendable {
    public let removedFiles: Int
    public let removedBytes: UInt64
    public let availableSpaceIncrease: UInt64?
    public let skippedFiles: Int
    public let issues: [String]
    public let cancelled: Bool
    public var runningApplications: [String] = []
}

public enum CleanerError: Error, LocalizedError {
    case staleScan, confirmationRequired, unsafePath, busy
    public var errorDescription: String? {
        switch self {
        case .staleScan: "Результаты устарели. Сначала повторите сканирование."
        case .confirmationRequired: "Для выбранных данных требуется дополнительное подтверждение."
        case .unsafePath: "Путь не прошёл проверку безопасности."
        case .busy: "Дождитесь завершения текущей операции."
        }
    }
}

struct CleanerTarget: Sendable {
    let category: CleanerCategory
    let name: String
    let relativePath: String
    var sensitive = false
    var canDelete = true
    var note: String? = nil
    var ownerIDs: [String] = []
}
