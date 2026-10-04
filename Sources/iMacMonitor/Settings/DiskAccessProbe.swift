import Darwin
import Foundation

/// A read-only capability probe, not an authoritative TCC authorization query.
actor DiskAccessProbe {
    enum Status: String, Sendable {
        case unknown = "Статус не определён"
        case readable = "Доступ к защищённому файлу подтверждён"
        case denied = "Доступ к защищённому файлу запрещён"
    }

    func check() -> Status {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        // Open only; never read the database contents or modify it.
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
        if descriptor >= 0 {
            Darwin.close(descriptor)
            return .readable
        }
        let code = errno
        return code == EACCES || code == EPERM ? .denied : .unknown
    }
}
