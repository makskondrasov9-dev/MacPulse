import Darwin
import Foundation
import Testing
@testable import MonitorCore

private struct UninstallFixture {
    let home: URL
    var apps: URL { home.appendingPathComponent("Applications") }
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-uninstall-test-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    }
    func write(_ relative: String, data: Data = Data("content".utf8)) throws -> URL {
        let path = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: path)
        return path
    }
    func app(_ name: String = "Example", id: String = "org.example.App") throws -> URL {
        let plist: [String: String] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": id,
            "CFBundleName": name, "CFBundleShortVersionString": "1.0", "CFBundleExecutable": "Example"]
        _ = try write("Applications/\(name).app/Contents/Info.plist", data: PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
        _ = try write("Applications/\(name).app/Contents/MacOS/Example", data: Data([0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1]))
        return apps.appendingPathComponent(name + ".app")
    }
    func service() -> UninstallerService { UninstallerService(home: home, roots: [apps]) }
    func dispose() { try? FileManager.default.removeItem(at: home) }
}

struct UninstallerTests {
    @Test func discoversMetadataAndPreviewOnlyExactOwnedPaths() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let cache = try f.write("Library/Caches/org.example.App/file")
        _ = try f.write("Library/Caches/org.example.AppOther/file")
        _ = try f.write("Library/Preferences/org.example.App.plist")
        _ = try f.write("Library/Application Support/Example/project")
        let service = f.service()
        let apps = try await service.applications()
        #expect(apps.count == 1)
        #expect(apps.first?.architecture == "Intel")
        let preview = try await service.preview(applicationURL: app)
        #expect(preview.items.count == 4)
        #expect(preview.items.contains { $0.nameMatch && $0.url.lastPathComponent == "Example" })
        #expect(preview.items.contains { $0.url == cache.deletingLastPathComponent() && !$0.nameMatch })
        #expect(preview.bytes > 0)
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func deletesOnlyCheckedItemsAfterConfirmation() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let keep = try f.write("Library/Application Support/Example/keep")
        let cache = try f.write("Library/Caches/org.example.App/cache")
        let service = f.service()
        let preview = try await service.preview(applicationURL: app)
        let selected = Set(preview.items.filter { !$0.nameMatch }.map(\.id))
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: selected, confirmed: false)
        }
        let result = try await service.remove(previewID: preview.id, selected: selected, confirmed: true)
        #expect(result.removedItems == 2)
        #expect(result.issues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: app.path))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: selected, confirmed: true)
        }
    }

    @Test func systemSelfMalformedAndNestedBundlesAreProtected() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let apple = try f.app("Apple", id: "com.apple.Example")
        let selfApp = try f.app("MacPulse", id: "LOCAL.IMACMONITOR")
        let invalid = try f.app("Invalid", id: "../../Documents")
        let service = f.service()
        for app in [apple, selfApp, invalid, URL(fileURLWithPath: "/System/Applications/Notes.app")] {
            await #expect(throws: (any Error).self) { try await service.preview(applicationURL: app) }
        }
        #expect(try await service.applications().isEmpty)
    }

    @Test func appAndResidueSymlinksCannotEscapeWhitelist() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let secret = try f.write("Documents/keep")
        let link = f.apps.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        let cache = f.home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("org.example.App"), withDestinationURL: secret.deletingLastPathComponent())
        let service = f.service()
        await #expect(throws: (any Error).self) { try await service.preview(applicationURL: link) }
        let preview = try await service.preview(applicationURL: app)
        #expect(preview.items.count == 1)
        #expect(!preview.issues.isEmpty)
        #expect(try String(contentsOf: secret, encoding: .utf8) == "content")
    }

    @Test func frameworkSymlinksAreRemovedWithoutTouchingTargets() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let secret = try f.write("Documents/keep")
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/Link"), withDestinationURL: secret)
        let service = f.service()
        let preview = try await service.preview(applicationURL: app)
        let result = try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        #expect(result.removedItems == 1 && result.issues.isEmpty)
        #expect(try String(contentsOf: secret, encoding: .utf8) == "content")
    }

    @Test func changedAndAddedFilesAbortBeforeAnyDeletion() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        _ = try f.write("Library/Caches/org.example.App/old")
        let service = f.service()
        let preview = try await service.preview(applicationURL: app)
        _ = try f.write("Library/Caches/org.example.App/new")
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        }
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func replacedParentAndBundleAreRejected() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        _ = try f.write("Library/Caches/org.example.App/cache")
        let service = f.service()
        let preview = try await service.preview(applicationURL: app)
        let original = f.home.appendingPathComponent("Library/Caches")
        let moved = f.home.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: moved)
        await #expect(throws: (any Error).self) {
            try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        }
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("org.example.App/cache").path))
    }

    @Test func runningAppsCannotBePreviewedOrRemoved() async throws {
        actor Running { var value = false; func set() { value = true } }
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let running = Running()
        let service = UninstallerService(home: f.home, roots: [f.apps], running: { _ in await running.value })
        let preview = try await service.preview(applicationURL: app)
        await running.set()
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        }
        await #expect(throws: UninstallerError.self) { try await service.preview(applicationURL: app) }
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func duplicateInstallationsPreserveSharedData() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let service = f.service()
        let cache = try f.write("Library/Caches/org.example.App/keep")
        let preview = try await service.preview(applicationURL: app)
        _ = try f.app("Second", id: "ORG.EXAMPLE.APP")
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        }
        let next = try await service.preview(applicationURL: app)
        #expect(next.items.count == 1)
        #expect(!next.issues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func dropFromHomeAndUnknownIDs() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let dropped = f.home.appendingPathComponent("Example.app")
        try FileManager.default.moveItem(at: app, to: dropped)
        let service = f.service()
        let preview = try await service.preview(applicationURL: dropped)
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: [UUID()], confirmed: true)
        }
        #expect(FileManager.default.fileExists(atPath: dropped.path))
    }

    @Test func cancelledRemovalPreservesEverySelectedItem() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let cache = try f.write("Library/Caches/org.example.App/cache")
        let service = f.service()
        let preview = try await service.preview(applicationURL: app)
        let deletion = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        }
        await #expect(throws: CancellationError.self) { try await deletion.value }
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func changedRootFileWithRestoredMtimeIsRejected() async throws {
        let f = try UninstallFixture(); defer { f.dispose() }
        let app = try f.app()
        let preferences = try f.write("Library/Preferences/org.example.App.plist")
        let service = f.service()
        let preview = try await service.preview(applicationURL: app)
        var before = stat()
        #expect(lstat(preferences.path, &before) == 0)
        try await Task.sleep(for: .milliseconds(5))
        try Data("changed".utf8).write(to: preferences)
        let times = [before.st_atimespec, before.st_mtimespec]
        #expect(times.withUnsafeBufferPointer { utimensat(AT_FDCWD, preferences.path, $0.baseAddress, 0) } == 0)
        await #expect(throws: UninstallerError.self) {
            try await service.remove(previewID: preview.id, selected: Set(preview.items.map(\.id)), confirmed: true)
        }
        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(FileManager.default.fileExists(atPath: preferences.path))
    }

    @Test func architectureHeaders() {
        #expect(ApplicationArchitecture.decode(Data([0xcf,0xfa,0xed,0xfe,12,0,0,1])) == "Apple Silicon")
        var fat: [UInt8] = [0xca,0xfe,0xba,0xbe,0,0,0,2]
        fat += [1,0,0,7] + Array(repeating: 0, count: 16)
        fat += [1,0,0,12] + Array(repeating: 0, count: 16)
        #expect(ApplicationArchitecture.decode(Data(fat)) == "Universal")
        #expect(ApplicationArchitecture.decode(Data(fat.prefix(12))) == "—")
        #expect(ApplicationArchitecture.decode(Data()) == "—")
    }
}
