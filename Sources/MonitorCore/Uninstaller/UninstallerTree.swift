import Darwin
import Foundation

/// Directory descriptors prevent traversal through substituted symlink parents.
/// Snapshots include every child, so files added after preview invalidate removal.
enum UninstallerTree {
    struct Node: Sendable, Equatable {
        let path: String
        let device: Int32
        let inode: UInt64
        let mode: UInt16
        let size: Int64
        let modified: Int
        let nanos: Int
        let changed: Int
        let changeNanos: Int
        init(_ path: String, _ info: stat) {
            self.path = path; device = info.st_dev; inode = info.st_ino; mode = info.st_mode
            size = info.st_size; modified = info.st_mtimespec.tv_sec; nanos = info.st_mtimespec.tv_nsec
            changed = info.st_ctimespec.tv_sec
            changeNanos = info.st_ctimespec.tv_nsec
        }
    }
    struct Snapshot: Sendable, Equatable {
        let nodes: [Node]
        func matchesClaimed(_ other: Snapshot) -> Bool {
            guard nodes.count == other.nodes.count else { return false }
            return zip(nodes, other.nodes).allSatisfy { before, after in
                if before.path.isEmpty && after.path.isEmpty {
                    // The atomic rename changes only the claimed root's ctime.
                    return before.device == after.device && before.inode == after.inode &&
                        before.mode == after.mode && before.size == after.size &&
                        before.modified == after.modified && before.nanos == after.nanos
                }
                return before == after
            }
        }
        var bytes: UInt64 { nodes.filter { $0.mode & S_IFMT != S_IFDIR }.reduce(0) { $0 + UInt64(max(0, $1.size)) } }
    }

    static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw UninstallerError.invalidApp }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posix() }
        var parts = url.path.split(separator: "/").map(String.init)
        // Foundation canonicalizes /private/var back to /var on macOS. Expand
        // only these fixed, root-owned system aliases; never resolve user paths.
        if let first = parts.first, ["var", "tmp", "etc"].contains(first) {
            var target = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let length = readlink("/" + first, &target, target.count)
            let link = length > 0 ? String(decoding: target.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
            guard link == "private/" + first || link == "/private/" + first else { close(fd); throw UninstallerError.invalidApp }
            parts.insert("private", at: 0)
        }
        for part in parts {
            guard part != ".", part != ".." else { close(fd); throw UninstallerError.invalidApp }
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw posix() }
            fd = next
        }
        return fd
    }

    static func scan(_ url: URL) throws -> Snapshot {
        let parent = try openDirectory(url.deletingLastPathComponent())
        defer { close(parent) }
        return try scan(parent: parent, leaf: url.lastPathComponent)
    }
    private static func scan(parent: Int32, leaf: String) throws -> Snapshot {
        var nodes: [Node] = []
        func walk(_ parent: Int32, _ leaf: String, _ path: String, _ depth: Int, _ device: Int32?) throws {
            try Task.checkCancellation()
            guard depth < 128 else { throw UninstallerError.invalidApp }
            var info = stat()
            guard fstatat(parent, leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posix() }
            if let device, device != info.st_dev { throw UninstallerError.protectedApp }
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFDIR || kind == S_IFREG || (!path.isEmpty && kind == S_IFLNK) else { throw UninstallerError.invalidApp }
            nodes.append(Node(path, info))
            guard kind == S_IFDIR else { return }
            let fd = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw posix() }
            guard let directory = fdopendir(fd) else { close(fd); throw posix() }
            defer { closedir(directory) }
            var opened = stat()
            guard fstat(fd, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else { throw UninstallerError.stale }
            while true {
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 { throw posix() }
                    break
                }
                var name = entry.pointee.d_name
                let child = withUnsafePointer(to: &name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if child == "." || child == ".." { continue }
                try walk(fd, child, path.isEmpty ? child : path + "/" + child, depth + 1, info.st_dev)
            }
        }
        try walk(parent, leaf, "", 0, nil)
        return Snapshot(nodes: nodes.sorted { $0.path < $1.path })
    }

    static func remove(_ url: URL, expected: Snapshot) throws {
        let parent = try openDirectory(url.deletingLastPathComponent())
        defer { close(parent) }
        guard try scan(parent: parent, leaf: url.lastPathComponent) == expected else { throw UninstallerError.stale }
        // Claim the exact root on the same filesystem before recursive Foundation deletion.
        let stageName = ".MacPulse-uninstall-" + UUID().uuidString
        guard mkdirat(parent, stageName, 0o700) == 0 else { throw posix() }
        let stage = openat(parent, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stage >= 0 else { unlinkat(parent, stageName, AT_REMOVEDIR); throw posix() }
        defer { close(stage); unlinkat(parent, stageName, AT_REMOVEDIR) }
        guard renameatx_np(parent, url.lastPathComponent, stage, "item", UInt32(RENAME_EXCL)) == 0 else { throw posix() }
        do {
            guard try expected.matchesClaimed(scan(parent: stage, leaf: "item")) else { throw UninstallerError.stale }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(stage, F_GETPATH, &buffer) == 0 else { throw posix() }
            let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            try FileManager.default.removeItem(at: URL(fileURLWithPath: path).appendingPathComponent("item"))
        } catch {
            if renameatx_np(stage, "item", parent, url.lastPathComponent, UInt32(RENAME_EXCL)) != 0 {
                throw NSError(domain: "MacPulse.Uninstaller", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    L("Не удалось восстановить файл. Проверьте: \(url.deletingLastPathComponent().appendingPathComponent(stageName).path)")])
            }
            throw error
        }
    }
    private static func posix() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
