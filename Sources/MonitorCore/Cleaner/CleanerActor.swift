import AppKit
import Darwin
import Foundation

public actor CleanerActor {
    private let home: URL
    private let applications: [URL]
    private let runningAppIDs: @Sendable () async -> Set<String>
    private let resolvesApplication: @Sendable (String) async -> Bool
    private var quickPreview = false
    private let fm = FileManager.default
    private var discoveryIssues: [String] = []
    private var busy = false
    private var scanID: UUID?
    private var preview: [UUID: (CleanerTarget, [FileRecord])] = [:]

    struct FileRecord: Sendable {
        let path: String
        let kind: mode_t
        let device: Int32
        let inode: UInt64
        let bytes: UInt64
        let modified: Int
        let modifiedNS: Int
        let changed: Int
        let changedNS: Int
    }

    public init() {
        runningAppIDs = { await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.flatMap { app in
                [app.bundleIdentifier, app.localizedName, app.bundleURL?.deletingPathExtension().lastPathComponent].compactMap { $0 }
            })
        } }
        resolvesApplication = { id in await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
        } }
        home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        applications = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
                        URL(fileURLWithPath: "/System/Applications")]
    }

    // Fixture-only injection stays internal: production callers cannot supply deletion roots.
    init(home: URL, applications: [URL] = [], runningApps: Set<String> = [], resolvedApps: Set<String> = []) {
        resolvesApplication = { resolvedApps.contains($0) }
        runningAppIDs = { runningApps }
        self.home = home.resolvingSymlinksInPath()
        self.applications = applications
    }

    public func scan(deepBrowsers: Bool = false,
                     progress: @Sendable (CleanerProgress) async -> Void = { _ in }) async throws -> CleanerScan {
        return try await buildScan(deepBrowsers: deepBrowsers, quick: false, progress: progress)
    }

    /// Explicit one-click action, restricted to caches, logs and Trash regardless of manual settings.
    public func quickClean(progress: @Sendable (CleanerProgress) async -> Void = { _ in }) async throws -> CleanerResult {
        let scan = try await buildScan(deepBrowsers: false, quick: true) { value in
            await progress(CleanerProgress(completed: value.completed, total: value.total, name: "Сканирование · " + value.name))
        }
        try Task.checkCancellation()
        if scan.items.isEmpty {
            return CleanerResult(removedFiles: 0, removedBytes: 0, availableSpaceIncrease: 0,
                                 skippedFiles: 0, issues: scan.issues, cancelled: false)
        }
        let result = try await delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true,
                                     sensitiveConfirmed: true) { value in
            await progress(CleanerProgress(completed: value.completed, total: value.total, name: "Удаление · " + value.name))
        }
        return CleanerResult(removedFiles: result.removedFiles, removedBytes: result.removedBytes,
            availableSpaceIncrease: result.availableSpaceIncrease, skippedFiles: result.skippedFiles,
            issues: scan.issues + scan.items.flatMap(\.issues) + result.issues, cancelled: result.cancelled,
            runningApplications: result.runningApplications)
    }

    private func buildScan(deepBrowsers: Bool, quick: Bool,
                           progress: @Sendable (CleanerProgress) async -> Void) async throws -> CleanerScan {
        guard !busy else { throw CleanerError.busy }
        busy = true
        defer { busy = false }
        scanID = nil
        preview.removeAll()
        discoveryIssues.removeAll()
        quickPreview = quick
        let targets = quick ? quickTargets() : try await discoverTargets(deep: deepBrowsers)
        var items: [CleanerItem] = []
        // Deduplicate overlapping roots and aliases; symlinks are never traversed.
        var seen: Set<String> = []
        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            await progress(CleanerProgress(completed: index, total: targets.count, name: target.name))
            var records: [FileRecord] = []
            var issues: [String] = []
            let root = home.appendingPathComponent(target.relativePath, isDirectory: false)
            do {
                guard let rootStat = try checkedStat(root) else { continue }
                var pending = [root]
                var visited = 0
                while let url = pending.popLast() {
                    try Task.checkCancellation()
                    visited += 1
                    if visited % 256 == 0 {
                        await progress(CleanerProgress(completed: index, total: targets.count,
                                                       name: "\(target.name) · проверено \(visited) объектов"))
                        await Task.yield()
                    }
                    do {
                        guard let info = try checkedStat(url), info.st_dev == rootStat.st_dev else { continue }
                        let kind = info.st_mode & mode_t(S_IFMT)
                        if kind == mode_t(S_IFDIR) {
                            // Preserve lexical paths, including dangling links. Foundation's
                            // standardization can rewrite /private/var aliases for missing targets.
                            let names = try fm.contentsOfDirectory(atPath: url.path)
                            pending.append(contentsOf: names.map { url.appendingPathComponent($0, isDirectory: false) })
                        } else if (kind == mode_t(S_IFREG) || kind == mode_t(S_IFLNK)), info.st_nlink == 1, seen.insert(url.path).inserted {
                            records.append(record(url, info))
                        }
                    } catch {
                        if issues.count < 10 { issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                    }
                }
            } catch {
                issues.append(error.localizedDescription)
            }
            guard !records.isEmpty || !issues.isEmpty else { continue }
            let id = UUID()
            preview[id] = (target, records)
            items.append(CleanerItem(id: id, category: target.category, name: target.name, path: root.path,
                bytes: records.reduce(0) { $0 + $1.bytes }, fileCount: records.count,
                sensitive: target.sensitive, canDelete: target.canDelete, note: target.note, issues: issues))
        }
        try Task.checkCancellation()
        let id = UUID()
        scanID = id
        await progress(CleanerProgress(completed: targets.count, total: targets.count, name: "Готово"))
        return CleanerScan(id: id, items: items, deepBrowsers: deepBrowsers, issues: discoveryIssues)
    }

    public func delete(scan id: UUID, selected: Set<UUID>, confirmed: Bool, sensitiveConfirmed: Bool,
                       progress: @Sendable (CleanerProgress) async -> Void = { _ in }) async throws -> CleanerResult {
        guard !busy else { throw CleanerError.busy }
        guard scanID == id, !selected.isEmpty, selected.allSatisfy({ preview[$0] != nil }) else { throw CleanerError.staleScan }
        let entries = selected.compactMap { preview[$0] }
        guard confirmed, entries.allSatisfy({ !$0.0.sensitive || sensitiveConfirmed }) else { throw CleanerError.confirmationRequired }
        guard entries.allSatisfy({ $0.0.canDelete }) else { throw CleanerError.unsafePath }
        busy = true
        defer { busy = false }
        // A scan is single-use, even if deletion is cancelled or partially fails.
        scanID = nil
        preview.removeAll()
        let allowedTargets = quickPreview ? quickTargets() : try await discoverTargets(deep: true)
        let allowed = Set(allowedTargets.filter(\.canDelete).map(\.relativePath))
        let running = await runningAppIDs()
        let before = availableSpace()
        let removal = try CleanerRemoval(home: home)
        let total = entries.reduce(0) { $0 + $1.1.count }
        var removed = 0, skipped = 0, processed = 0
        var bytes: UInt64 = 0
        var issues: [String] = []
        var cancelled = false
        var skippedApps: Set<String> = []
        for (target, files) in entries {
            let openOwners = running.intersection(target.ownerIDs)
            if !openOwners.isEmpty {
                skipped += files.count
                processed += files.count
                skippedApps.formUnion(openOwners.map(CleanerCatalog.applicationName))
                issues.append("\(target.name): пропущено \(files.count) файлов — приложение открыто.")
                continue
            }
            guard allowed.contains(target.relativePath) else {
                skipped += files.count
                processed += files.count
                issues.append("\(target.name): путь больше не разрешён для очистки.")
                continue
            }
            for file in files {
                if Task.isCancelled { cancelled = true; break }
                processed += 1
                if processed % 64 == 0 || processed == 1 {
                    await progress(CleanerProgress(completed: processed, total: total, name: target.name))
                }
                if Task.isCancelled { cancelled = true; break }
                do {
                    let url = URL(fileURLWithPath: file.path, isDirectory: false)
                    let root = home.appendingPathComponent(target.relativePath, isDirectory: false)
                    guard url.path == root.path || url.path.hasPrefix(root.path + "/"),
                          let current = try checkedStat(url), matches(file, current) else {
                        throw CleanerError.staleScan
                    }
                    // Only snapshot files or cache leaf links, never a recursively removed root.
                    // New files created after the scan are not part of this operation.
                    try removal.remove(file)
                    removed += 1
                    bytes += file.bytes
                } catch {
                    skipped += 1
                    if issues.count < 50 { issues.append("\(file.path): \(error.localizedDescription)") }
                }
            }
            if cancelled { break }
        }
        let after = availableSpace()
        let growth = before.flatMap { before in after.map { $0 > before ? $0 - before : 0 } }
        await progress(CleanerProgress(completed: processed, total: total, name: cancelled ? "Остановлено" : "Готово"))
        return CleanerResult(removedFiles: removed, removedBytes: bytes, availableSpaceIncrease: growth,
                             skippedFiles: skipped, issues: issues, cancelled: cancelled,
                             runningApplications: skippedApps.sorted())
    }

    private func availableSpace() -> UInt64? {
        (try? fm.attributesOfFileSystem(forPath: home.path)[.systemFreeSize] as? NSNumber)?.uint64Value
    }

    /// Checks every component, so a symlinked parent cannot escape an approved root.
    private func checkedStat(_ url: URL) throws -> stat? {
        guard url.path.hasPrefix(home.path + "/") else { throw CleanerError.unsafePath }
        let relative = String(url.path.dropFirst(home.path.count + 1))
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !["Documents", "Desktop", "Applications"].contains(parts[0]),
              !parts.contains(".."), !parts.contains(".") else { throw CleanerError.unsafePath }
        var path = home.path
        var info = stat()
        for (index, part) in parts.enumerated() {
            path += "/" + part
            guard lstat(path, &info) == 0 else {
                if errno == ENOENT { return nil }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
                // Only the leaf link itself is eligible, never a linked ancestor or target.
                guard index == parts.count - 1, parts.count > 2,
                      parts[0] == "Library", parts[1] == "Caches" else { throw CleanerError.unsafePath }
            }
        }
        return info
    }

    private func record(_ url: URL, _ info: stat) -> FileRecord {
        FileRecord(path: url.path, kind: info.st_mode & mode_t(S_IFMT), device: info.st_dev, inode: UInt64(info.st_ino), bytes: UInt64(max(0, info.st_size)),
                   modified: info.st_mtimespec.tv_sec, modifiedNS: info.st_mtimespec.tv_nsec,
                   changed: info.st_ctimespec.tv_sec, changedNS: info.st_ctimespec.tv_nsec)
    }

    private func matches(_ file: FileRecord, _ info: stat) -> Bool {
        info.st_mode & mode_t(S_IFMT) == file.kind && info.st_nlink == 1 && info.st_dev == file.device &&
        UInt64(info.st_ino) == file.inode && UInt64(max(0, info.st_size)) == file.bytes &&
        info.st_mtimespec.tv_sec == file.modified && info.st_mtimespec.tv_nsec == file.modifiedNS &&
        info.st_ctimespec.tv_sec == file.changed && info.st_ctimespec.tv_nsec == file.changedNS
    }

    private func children(_ relative: String) -> [String] {
        let url = home.appendingPathComponent(relative, isDirectory: false)
        do {
            guard let info = try checkedStat(url) else { return [] }
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw CleanerError.unsafePath }
            return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        } catch {
            if discoveryIssues.count < 20 { discoveryIssues.append("\(url.path): \(error.localizedDescription)") }
            return []
        }
    }

    private func quickTargets() -> [CleanerTarget] {
        let browsers = ["com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "company.thebrowser.Browser",
                        "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware.Opera"]
        // The only dynamic roots are immediate children of the user cache directory.
        // Revalidate every path component during scan and deletion; never follow links.
        var targets = children("Library/Caches").filter { !$0.hasPrefix(".MacPulse-delete-") }.map { folder in
            CleanerTarget(category: .media, name: "Кэш · " + folder, relativePath: "Library/Caches/" + folder,
                          ownerIDs: CleanerCatalog.browserCaches.contains(where: { $0 == folder || $0.hasPrefix(folder + "/") }) ? browsers : CleanerCatalog.cacheOwners(folder))
        }
        targets.append(CleanerTarget(category: .system, name: "Логи и отчёты", relativePath: "Library/Logs"))
        targets.append(CleanerTarget(category: .system, name: "Корзина", relativePath: ".Trash", sensitive: true))
        return targets
    }

    private func discoverTargets(deep: Bool) async throws -> [CleanerTarget] {
        var targets = CleanerCatalog.standard()
        for version in children("Library/Application Support/Ableton") where version.hasPrefix("Live ") {
            for sub in ["Database", "Cache"] {
                targets.append(CleanerTarget(category: .audio, name: "Ableton \(version) · \(sub)",
                    relativePath: "Library/Application Support/Ableton/\(version)/\(sub)", sensitive: true,
                    note: "Закройте Ableton. База может содержать индекс и пользовательские коллекции; сохраните резервную копию."))
            }
        }
        // Only derived render/freeze directories; never media originals or project bundles.
        for library in children("Movies") where library.hasSuffix(".fcpbundle") {
            for event in children("Movies/\(library)") {
                targets.append(CleanerTarget(category: .video, name: "Final Cut · \(library) / \(event)",
                    relativePath: "Movies/\(library)/\(event)/Render Files", sensitive: true,
                    note: "Только Render Files. Для восстановления нужен повторный рендер."))
            }
        }
        for folder in ["Music/Logic", "Music/GarageBand"] {
            for project in children(folder) where project.hasSuffix(".logicx") || project.hasSuffix(".band") {
                targets.append(CleanerTarget(category: .audio, name: "Freeze · \(project)",
                    relativePath: "\(folder)/\(project)/Freeze Files", sensitive: true,
                    note: "Только замороженные дорожки. Для восстановления нужны исходники и плагины."))
            }
        }
        if deep {
            for (browser, base) in CleanerCatalog.chromiumProfiles {
                let profiles = children(base).filter { $0 == "Default" || $0.hasPrefix("Profile ") }
                for profile in profiles {
                    for leaf in CleanerCatalog.chromiumSiteData {
                        targets.append(CleanerTarget(category: .browsers, name: "\(browser) · \(profile) · \(leaf)",
                            relativePath: "\(base)/\(profile)/\(leaf)", sensitive: true,
                            note: "Глубокая очистка: выход из аккаунтов, потеря локальных данных сайтов."))
                    }
                }
            }
            let base = "Library/Application Support/Firefox/Profiles"
            for profile in children(base) {
                for leaf in CleanerCatalog.firefoxSiteData {
                    targets.append(CleanerTarget(category: .browsers, name: "Firefox · \(profile) · \(leaf)",
                        relativePath: "\(base)/\(profile)/\(leaf)", sensitive: true,
                        note: "Глубокая очистка: cookies и локальные данные сайтов."))
                }
            }
            for path in ["Library/Cookies/Cookies.binarycookies", "Library/WebKit/com.apple.Safari/WebsiteData",
                         "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
                         "Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData"] {
                targets.append(CleanerTarget(category: .browsers, name: "Safari · данные сайтов", relativePath: path,
                    sensitive: true, note: "Глубокая очистка: cookies и данные сайтов Safari."))
            }
        }
        let installed = installedApps()
        if !installed.complete {
            discoveryIssues.append("Не удалось полностью проверить список приложений. Удаление предполагаемых остатков отключено.")
        }
        let support = "Library/Application Support"
        let ownedRoots = Set(targets.compactMap { target -> String? in
            guard target.relativePath.hasPrefix(support + "/") else { return nil }
            return target.relativePath.dropFirst(support.count + 1).split(separator: "/").first.map(String.init)
        })
        let browserOwners: Set<String> = ["Google", "BraveSoftware", "Arc", "Firefox", "Microsoft Edge", "com.operasoftware.Opera", "com.apple.Safari"]
        let running = await runningAppIDs()
        let runningNames = Set(running.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } })
        for folder in children(support) where !ownedRoots.contains(folder) && !browserOwners.contains(folder) {
            try Task.checkCancellation()
            guard !folder.lowercased().hasPrefix("com.apple.") else { continue }
            let owner = CleanerCatalog.knownOwners.first { $0.folder == folder }
            let candidateIDs = [folder] + (owner?.ids ?? [])
            let names = [folder, owner?.app ?? folder].map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            guard running.isDisjoint(with: candidateIDs),
                  !names.contains(where: { name in runningNames.contains(where: { $0.count >= 4 && (name.hasPrefix($0) || $0.hasPrefix(name)) }) }) else { continue }
            // G Hub runs helper bundles as well as its main application.
            if folder.lowercased().hasPrefix("lghub"), running.contains(where: {
                $0.lowercased().contains("ghub") || $0.lowercased().contains("g hub")
            }) { continue }
            var resolved = false
            for id in candidateIDs {
                if await resolvesApplication(id) { resolved = true; break }
            }
            guard !resolved else { continue }
            guard !installed.names.contains(folder.lowercased()), !installed.ids.contains(folder) else { continue }
            if let owner = CleanerCatalog.knownOwners.first(where: { $0.folder == folder }) {
                guard !installed.names.contains(owner.app.lowercased()), installed.ids.isDisjoint(with: owner.ids) else { continue }
                targets.append(CleanerTarget(category: .orphaned, name: "\(owner.app) · возможный остаток",
                    relativePath: "\(support)/\(folder)", sensitive: true, canDelete: installed.complete,
                    note: "Приложение не найдено в стандартных папках. Здесь могут быть пользовательские данные. Проверьте другие диски и папки.", ownerIDs: owner.ids))
            } else {
                // A folder name is not sufficient proof of abandonment. Inventory only.
                targets.append(CleanerTarget(category: .orphaned, name: folder,
                    relativePath: "\(support)/\(folder)", sensitive: true, canDelete: false,
                    note: "Владелец не установлен достоверно. Только просмотр; удаление заблокировано."))
            }
        }
        for index in targets.indices where targets[index].category == .browsers {
            // All browser processes must be closed for either browser mode.
            targets[index].ownerIDs = ["com.apple.Safari", "com.google.Chrome", "com.brave.Browser",
                                      "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware.Opera"]
        }
        return targets
    }

    private func installedApps() -> (names: Set<String>, ids: Set<String>, complete: Bool) {
        var names: Set<String> = [], ids: Set<String> = []
        var complete = true
        for root in applications {
            do { _ = try fm.attributesOfItem(atPath: root.path) }
            catch let error as NSError {
                if error.code != NSFileReadNoSuchFileError && error.code != NSFileNoSuchFileError { complete = false }
                continue
            }
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                               errorHandler: { _, _ in complete = false; return true }) else {
                complete = false
                continue
            }
            for case let app as URL in iterator where app.pathExtension == "app" {
                names.insert(app.deletingPathExtension().lastPathComponent.lowercased())
                if let id = Bundle(url: app)?.bundleIdentifier { ids.insert(id) }
            }
        }
        return (names, ids, complete)
    }
}
