import Foundation
import Testing
@testable import MonitorCore

private struct CleanerFixture {
    let home: URL
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-tests-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    func write(_ path: String, _ value: String = "cache") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
        return url
    }
    func dispose() { try? FileManager.default.removeItem(at: home) }
}

struct CleanerTests {
    @Test func safeBrowserModeDoesNotScanProfilesOrRemoveOtherCategories() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let cache = try fixture.write("Library/Caches/com.google.Chrome/cache", "123456")
        let cookies = try fixture.write("Library/Application Support/Google/Chrome/Default/Cookies", "secret")
        let log = try fixture.write("Library/Logs/log")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        #expect(!scan.items.contains { $0.path.contains("Application Support/Google") })
        let item = try #require(scan.items.first { $0.category == .browsers })
        #expect(item.bytes == 6 && item.fileCount == 1)
        let result = try await engine.delete(scan: scan.id, selected: [item.id], confirmed: true, sensitiveConfirmed: false)
        #expect(result.removedFiles == 1 && result.removedBytes == 6)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(FileManager.default.fileExists(atPath: cookies.path))
        #expect(FileManager.default.fileExists(atPath: log.path))
    }

    @Test func deepBrowserModeRequiresConfirmationAndPreservesPasswords() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let cookies = try fixture.write("Library/Application Support/Google/Chrome/Default/Cookies")
        let password = try fixture.write("Library/Application Support/Google/Chrome/Default/Login Data")
        let bookmark = try fixture.write("Library/Application Support/Google/Chrome/Default/Bookmarks")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan(deepBrowsers: true)
        let item = try #require(scan.items.first { $0.path == cookies.path })
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: scan.id, selected: [item.id], confirmed: true, sensitiveConfirmed: false)
        }
        #expect(FileManager.default.fileExists(atPath: cookies.path))
        let result = try await engine.delete(scan: scan.id, selected: [item.id], confirmed: true, sensitiveConfirmed: true)
        #expect(result.removedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: password.path))
        #expect(FileManager.default.fileExists(atPath: bookmark.path))
    }

    @Test func cacheLinksAreRemovedButHardlinksAndProtectedTargetsArePreserved() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let original = try fixture.write("Documents/keep", "important")
        let cache = try fixture.write("Library/Caches/com.apple.FinalCut/cache")
        let parent = cache.deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("link"), withDestinationURL: original)
        try FileManager.default.linkItem(at: original, to: parent.appendingPathComponent("hardlink"))
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        let item = try #require(scan.items.first { $0.category == .video })
        #expect(item.fileCount == 2)
        _ = try await engine.delete(scan: scan.id, selected: [item.id], confirmed: true, sensitiveConfirmed: false)
        #expect(try String(contentsOf: original, encoding: .utf8) == "important")
    }

    @Test func swappedParentAndChangedFilesAreNotDeleted() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let log = try fixture.write("Library/Logs/log", "old")
        let cache = try fixture.write("Library/Caches/com.apple.FinalCut/cache")
        let important = try fixture.write("Desktop/keep/cache", "valuable")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        try Data("new content".utf8).write(to: log)
        let parent = cache.deletingLastPathComponent()
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: important.deletingLastPathComponent())
        let result = try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        #expect(result.removedFiles == 0 && result.skippedFiles == 2)
        #expect(try String(contentsOf: important, encoding: .utf8) == "valuable")
        #expect(try String(contentsOf: log, encoding: .utf8) == "new content")
    }

    @Test func replacedFileWithDirectoryIsNotRecursivelyRemoved() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let file = try fixture.write("Library/Logs/entry")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        try FileManager.default.removeItem(at: file)
        let nested = try fixture.write("Library/Logs/entry/new-data")
        let result = try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        #expect(result.removedFiles == 0)
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func unknownOrphanIsInventoryOnlyAndArchivesNeedConsent() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let unknown = try fixture.write("Library/Application Support/Mystery/data")
        let archive = try fixture.write("Library/Developer/Xcode/Archives/Release/archive")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        let orphan = try #require(scan.items.first { $0.category == .orphaned })
        #expect(!orphan.canDelete)
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: scan.id, selected: [orphan.id], confirmed: true, sensitiveConfirmed: true)
        }
        let archives = try #require(scan.items.first { $0.name.contains("Archives") })
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: scan.id, selected: [archives.id], confirmed: true, sensitiveConfirmed: false)
        }
        #expect(FileManager.default.fileExists(atPath: unknown.path))
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func previewCannotBeReusedOrForged() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        _ = try fixture.write("Library/Logs/log")
        let engine = CleanerActor(home: fixture.home)
        let old = try await engine.scan()
        let current = try await engine.scan()
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: old.id, selected: Set(old.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        }
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: current.id, selected: [UUID()], confirmed: true, sensitiveConfirmed: true)
        }
        _ = try await engine.delete(scan: current.id, selected: Set(current.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: current.id, selected: Set(current.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        }
    }

    @Test func runningBrowserBlocksDeletion() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let file = try fixture.write("Library/Caches/com.google.Chrome/cache")
        let engine = CleanerActor(home: fixture.home, runningApps: ["com.google.Chrome"])
        let scan = try await engine.scan()
        let result = try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        #expect(result.removedFiles == 0 && result.skippedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func cancelledScanDoesNotDelete() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let file = try fixture.write("Library/Logs/log")
        let engine = CleanerActor(home: fixture.home)
        let task = Task { try await engine.scan() }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {} catch { throw error }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func cancellationBeforeDeletionPreservesFilesAndInvalidatesPreview() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        let file = try fixture.write("Library/Logs/log")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        let worker = Task {
            try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true,
                                    sensitiveConfirmed: true) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let result = try await worker.value
        #expect(result.cancelled && result.removedFiles == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
        await #expect(throws: CleanerError.self) {
            try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        }
    }

    @Test func newFilesAfterPreviewArePreserved() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        _ = try fixture.write("Library/Logs/old")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        let fresh = try fixture.write("Library/Logs/new")
        let result = try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        #expect(result.removedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func finalCutRendersAreSelectableButOriginalMediaIsNot() async throws {
        let fixture = try CleanerFixture(); defer { fixture.dispose() }
        _ = try fixture.write("Movies/Edit.fcpbundle/Event/Render Files/render")
        let original = try fixture.write("Movies/Edit.fcpbundle/Event/Original Media/clip.mov")
        let engine = CleanerActor(home: fixture.home)
        let scan = try await engine.scan()
        let render = try #require(scan.items.first { $0.name.hasPrefix("Final Cut ·") })
        #expect(render.fileCount == 1 && render.sensitive)
        let result = try await engine.delete(scan: scan.id, selected: [render.id], confirmed: true, sensitiveConfirmed: true)
        #expect(result.removedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

}
