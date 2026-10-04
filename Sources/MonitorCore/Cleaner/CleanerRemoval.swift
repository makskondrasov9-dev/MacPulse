import Darwin
import Foundation

/// Anchors source traversal to directory descriptors and atomically moves each
/// file into a private staging directory before Foundation removes it. This
/// avoids recursive deletion of a directory substituted for a scanned file.
final class CleanerRemoval {
    private let home: URL
    private let cacheFD: Int32
    private let stageFD: Int32
    private let stageName: String

    init(home: URL) throws {
        self.home = home
        // Create the staging parent only if its existing ancestors are real dirs.
        var cursor = home
        for component in ["Library", "Caches"] {
            cursor.appendPathComponent(component)
            var info = stat()
            if lstat(cursor.path, &info) != 0 {
                guard errno == ENOENT else { throw CleanerError.unsafePath }
                try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: false)
            } else if info.st_mode & mode_t(S_IFMT) != mode_t(S_IFDIR) { throw CleanerError.unsafePath }
        }
        let cache = try Self.openDirectory(home: home, components: ["Library", "Caches"])
        let name = ".MacPulse-delete-" + UUID().uuidString
        guard mkdirat(cache, name, 0o700) == 0 else { close(cache); throw CleanerError.unsafePath }
        let stage = openat(cache, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stage >= 0 else { unlinkat(cache, name, AT_REMOVEDIR); close(cache); throw CleanerError.unsafePath }
        cacheFD = cache
        stageFD = stage
        stageName = name
    }

    deinit {
        // Removes an empty directory only. A failed restoration remains for recovery.
        unlinkat(cacheFD, stageName, AT_REMOVEDIR)
        close(stageFD)
        close(cacheFD)
    }

    func remove(_ file: CleanerActor.FileRecord) throws {
        guard file.path.hasPrefix(home.path + "/") else { throw CleanerError.unsafePath }
        let parts = file.path.dropFirst(home.path.count + 1).split(separator: "/").map(String.init)
        guard let leaf = parts.last,
              file.kind == mode_t(S_IFREG) || (file.kind == mode_t(S_IFLNK) && parts.count > 2 &&
                  parts[0] == "Library" && parts[1] == "Caches") else { throw CleanerError.unsafePath }
        let parent = try Self.openDirectory(home: home, components: Array(parts.dropLast()))
        defer { close(parent) }
        var before = stat()
        guard fstatat(parent, leaf, &before, AT_SYMLINK_NOFOLLOW) == 0,
              Self.matches(file, before, includeChangeTime: true) else { throw CleanerError.staleScan }
        let claimed = UUID().uuidString
        guard renameatx_np(parent, leaf, stageFD, claimed, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        do {
            var moved = stat()
            guard fstatat(stageFD, claimed, &moved, AT_SYMLINK_NOFOLLOW) == 0,
                  Self.matches(file, moved, includeChangeTime: false) else { throw CleanerError.staleScan }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(stageFD, F_GETPATH, &path) == 0 else { throw CleanerError.unsafePath }
            let directory = URL(fileURLWithPath: String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self))
            let staged = directory.appendingPathComponent(claimed, isDirectory: false)
            try FileManager.default.removeItem(at: staged)
        } catch {
            // Never overwrite a new file created at the original name.
            if renameatx_np(stageFD, claimed, parent, leaf, UInt32(RENAME_EXCL)) != 0 {
                throw NSError(domain: "MacPulse.Cleaner", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Файл сохранён для восстановления: Library/Caches/\(stageName)/\(claimed). \(error.localizedDescription)"])
            }
            throw error
        }
    }

    private static func openDirectory(home: URL, components: [String]) throws -> Int32 {
        var descriptor = open(home.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CleanerError.unsafePath }
        for component in components {
            guard component != ".", component != "..", !component.contains("/") else {
                close(descriptor); throw CleanerError.unsafePath
            }
            let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { throw CleanerError.unsafePath }
            descriptor = next
        }
        return descriptor
    }

    private static func matches(_ file: CleanerActor.FileRecord, _ info: stat, includeChangeTime: Bool) -> Bool {
        info.st_mode & mode_t(S_IFMT) == file.kind && info.st_nlink == 1 && info.st_dev == file.device &&
        UInt64(info.st_ino) == file.inode && UInt64(max(0, info.st_size)) == file.bytes &&
        info.st_mtimespec.tv_sec == file.modified && info.st_mtimespec.tv_nsec == file.modifiedNS &&
        (!includeChangeTime || (info.st_ctimespec.tv_sec == file.changed && info.st_ctimespec.tv_nsec == file.changedNS))
    }
}
