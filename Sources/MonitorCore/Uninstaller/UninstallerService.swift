import AppKit
import Darwin
import Foundation

/// Owns discovery, preview identity and deletion. UI supplies only preview/item IDs,
/// never arbitrary deletion paths. All filesystem work runs outside the main actor.
public actor UninstallerService {
    private let home: URL
    private let roots: [URL]
    private let running: @Sendable (InstalledApplication) async -> Bool
    private var busy = false
    private var saved: UninstallerPreview?
    private var snapshots: [UUID: UninstallerTree.Snapshot] = [:]
    private let fm = FileManager.default

    public init() {
        home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        running = { app in
            let workspace = await MainActor.run {
                NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier?.caseInsensitiveCompare(app.bundleID) == .orderedSame || $0.bundleURL?.resolvingSymlinksInPath() == app.url
                }
            }
            if workspace { return true }
            var processes = ProcessService()
            return processes.sample().contains { $0.executablePath.hasPrefix(app.url.path + "/") }
        }
    }
    // Fixtures cannot change production deletion roots through the public API.
    init(home: URL, roots: [URL], running: @escaping @Sendable (InstalledApplication) async -> Bool = { _ in false }) {
        self.home = home.resolvingSymlinksInPath(); self.roots = roots; self.running = running
    }

    public func applications() throws -> [InstalledApplication] {
        guard !busy else { throw UninstallerError.busy }
        return try discover()
    }
    private func discover() throws -> [InstalledApplication] {
        var apps: [InstalledApplication] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    if let app = try? application(at: url) { apps.append(app) }
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func application(at input: URL) throws -> InstalledApplication {
        guard input.isFileURL else { throw UninstallerError.invalidApp }
        let url = input.standardizedFileURL
        guard url.pathExtension.lowercased() == "app",
              !url.pathComponents.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") }),
              !["/System/", "/Library/", "/usr/", "/bin/", "/sbin/"].contains(where: { url.path.hasPrefix($0) }),
              !url.path.hasPrefix(home.appendingPathComponent("Library").path + "/")
        else { throw UninstallerError.protectedApp }
        // Open every ancestor without following links, including the bundle itself.
        let fd = try UninstallerTree.openDirectory(url)
        close(fd)
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let metadata = try UninstallerTree.scan(infoURL) // Reject a symlinked Contents or plist.
        guard metadata.nodes.count == 1, metadata.bytes <= 2_000_000 else { throw UninstallerError.invalidApp }
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        guard let info, info["CFBundlePackageType"] as? String == "APPL",
              let id = info["CFBundleIdentifier"] as? String, Self.validID(id) else { throw UninstallerError.invalidApp }
        guard !id.lowercased().hasPrefix("com.apple."), id.lowercased() != "local.imacmonitor",
              id.lowercased() != Bundle.main.bundleIdentifier?.lowercased(),
              url != Bundle.main.bundleURL.resolvingSymlinksInPath() else { throw UninstallerError.protectedApp }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        var architecture = "—"
        if let executable = info["CFBundleExecutable"] as? String, Self.validComponent(executable) {
            let path = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
            if (try? UninstallerTree.scan(path)) != nil { architecture = ApplicationArchitecture.read(path) }
        }
        return InstalledApplication(url: url, name: name, bundleID: id,
            version: info["CFBundleShortVersionString"] as? String ?? "—", architecture: architecture)
    }

    public func preview(applicationURL: URL) async throws -> UninstallerPreview {
        guard !busy else { throw UninstallerError.busy }
        busy = true
        defer { busy = false }
        saved = nil; snapshots = [:]
        let app = try application(at: applicationURL)
        guard !(await running(app)) else { throw UninstallerError.running }
        let others = try discover().filter { $0.url != app.url }
        let duplicate = others.contains { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }
        var candidates: [(URL, Bool, Bool)] = [(app.url, true, false)]
        var issues: [String] = []
        if duplicate { issues.append(UninstallerError.sharedData.localizedDescription) }
        else {
            for (directory, suffix) in [("Application Support", ""), ("Caches", ""), ("Preferences", ".plist"),
                ("Saved Application State", ".savedState"), ("Containers", ""), ("HTTPStorages", ""), ("WebKit", "")] {
                candidates.append((home.appendingPathComponent("Library/" + directory).appendingPathComponent(app.bundleID + suffix), false, false))
            }
            let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent])
            for name in names where Self.validComponent(name) && !Self.genericNames.contains(name.lowercased()) &&
                !others.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }) {
                if name != app.bundleID {
                    candidates.append((home.appendingPathComponent("Library/Application Support").appendingPathComponent(name), false, true))
                }
            }
        }
        var items: [UninstallerItem] = []
        var identities = Set<String>()
        for (url, isApp, nameMatch) in candidates {
            try Task.checkCancellation()
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                if errno != ENOENT { issues.append(url.path + ": " + String(cString: strerror(errno))) }
                continue
            }
            do {
                let tree = try UninstallerTree.scan(url)
                guard let root = tree.nodes.first, identities.insert("\(root.device):\(root.inode)").inserted else { continue }
                let item = UninstallerItem(id: UUID(), url: url, bytes: tree.bytes, isApplication: isApp, nameMatch: nameMatch)
                snapshots[item.id] = tree
                items.append(item)
            } catch {
                if isApp { throw error }
                issues.append(url.path + ": " + error.localizedDescription)
            }
        }
        let preview = UninstallerPreview(id: UUID(), application: app, items: items, issues: issues)
        guard items.contains(where: \.isApplication) else { throw UninstallerError.stale }
        saved = preview
        return preview
    }

    public func remove(previewID: UUID, selected: Set<UUID>, confirmed: Bool) async throws -> UninstallerResult {
        guard !busy else { throw UninstallerError.busy }
        guard confirmed, let preview = saved, preview.id == previewID,
              !selected.isEmpty, selected.isSubset(of: Set(preview.items.map(\.id))) else { throw UninstallerError.stale }
        busy = true
        defer { busy = false; saved = nil; snapshots = [:] }
        let app = try application(at: preview.application.url)
        guard app == preview.application else { throw UninstallerError.stale }
        guard !(await running(app)) else { throw UninstallerError.running }
        let others = try discover().filter { $0.url != app.url }
        if preview.items.contains(where: { selected.contains($0.id) && !$0.isApplication }),
           others.contains(where: { $0.bundleID.caseInsensitiveCompare(app.bundleID) == .orderedSame }) { throw UninstallerError.sharedData }
        let items = preview.items.filter { selected.contains($0.id) }
        // Validate the entire selection before the first irreversible action.
        for item in items {
            try Task.checkCancellation()
            guard let tree = snapshots[item.id], try UninstallerTree.scan(item.url) == tree else { throw UninstallerError.stale }
            if item.nameMatch && others.contains(where: { $0.name.caseInsensitiveCompare(item.url.lastPathComponent) == .orderedSame ||
                $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(item.url.lastPathComponent) == .orderedSame }) {
                throw UninstallerError.sharedData
            }
        }
        guard !(await running(app)) else { throw UninstallerError.running }
        var result = UninstallerResult()
        for item in items { // App goes first. A failure leaves its data untouched.
            if Task.isCancelled { result.issues.append(L("Удаление остановлено.")); break }
            do {
                guard let expected = snapshots[item.id] else { throw UninstallerError.stale }
                try UninstallerTree.remove(item.url, expected: expected)
                result.removedItems += 1; result.removedBytes += item.bytes
            } catch {
                result.issues.append(item.url.path + ": " + error.localizedDescription)
                if item.isApplication { break }
            }
        }
        return result
    }

    private static let genericNames: Set<String> = ["apple", "adobe", "microsoft", "google", "library", "containers", "application support", "caches", "preferences", "saved application state", "webkit", "httpstorages"]
    private static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0") && !value.hasPrefix(".")
    }
    private static func validID(_ value: String) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).count >= 2 &&
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty } &&
        value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }
    }
}
