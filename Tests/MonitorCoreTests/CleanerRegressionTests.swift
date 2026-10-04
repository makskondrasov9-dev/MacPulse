import Foundation
import Testing
@testable import MonitorCore

struct CleanerRegressionTests {
    private func fixture() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
    private func write(_ path: String, in home: URL) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        return url
    }

    @Test func quickCleanIsConfinedToCachesLogsAndTrash() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let eligible = try ["Library/Caches/com.google.Chrome/cache", "Library/Caches/Example/cache",
                            "Library/Logs/DiagnosticReports/crash", ".Trash/file"].map { try write($0, in: home) }
        let protected = try ["Library/Application Support/Google/Chrome/Default/Cookies",
                             "Library/Application Support/Example/data", "Library/Developer/Xcode/Archives/archive",
                             "Documents/document", "Desktop/file"].map { try write($0, in: home) }
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Caches/escape"),
                                                   withDestinationURL: home.appendingPathComponent("Documents"))
        let result = try await CleanerActor(home: home).quickClean()
        #expect(result.removedFiles == 5)
        #expect(result.issues.isEmpty)
        #expect(eligible.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(protected.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func quickCleanSkipsRunningBrowserButCleansOtherCaches() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let browser = try write("Library/Caches/Google/Chrome/cache", in: home)
        let cache = try write("Library/Caches/Example/cache", in: home)
        let result = try await CleanerActor(home: home, runningApps: ["com.google.Chrome"]).quickClean()
        #expect(result.removedFiles == 1 && result.skippedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: browser.path))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func quickCancellationDuringScanDoesNotDelete() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let file = try write(".Trash/file", in: home)
        let worker = Task {
            try await CleanerActor(home: home).quickClean { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func appleServicesRunningHelpersAndResolvedAppsAreNotOrphans() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        for folder in ["com.apple.sbd", "com.apple.control-center.tips", "LGHUBData", "com.example.external", "Slack", "Unknown"] {
            _ = try write("Library/Application Support/" + folder + "/data", in: home)
        }
        let engine = CleanerActor(home: home, runningApps: ["com.logi.ghub.agent"],
                                  resolvedApps: ["com.example.external", "com.tinyspeck.slackmacgap"])
        let scan = try await engine.scan()
        let leftovers = scan.items.filter { $0.category == .orphaned }
        #expect(leftovers.count == 1)
        #expect(leftovers.first?.name == "Unknown")
        #expect(leftovers.first?.canDelete == false)
    }

    @Test func homebrewArchivesAndFrameworkLinksAreCleanedWithoutFollowingLinks() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let outside = try write("Documents/valuable", in: home)
        let archives = try ["libvmaf.tar.gz", "curl.tar.bz2", "bottle_manifest.json"].map {
            try write("Library/Caches/Homebrew/downloads/" + $0, in: home)
        }
        let base = home.appendingPathComponent("Library/Caches/Homebrew")
        for name in ["Current", "Resources", "Mantle", "Squirrel", "ReactiveObjC"] {
            try FileManager.default.createSymbolicLink(at: base.appendingPathComponent(name), withDestinationURL: outside)
        }
        try FileManager.default.createSymbolicLink(atPath: base.appendingPathComponent("dangling").path, withDestinationPath: "missing")
        let engine = CleanerActor(home: home)
        let scan = try await engine.scan()
        let item = try #require(scan.items.first { $0.name.hasPrefix("Homebrew") })
        #expect(item.fileCount == 9)
        #expect(item.issues.isEmpty)
        let result = try await engine.delete(scan: scan.id, selected: [item.id], confirmed: true, sensitiveConfirmed: false)
        #expect(result.removedFiles == 9)
        #expect(result.issues.isEmpty)
        #expect(archives.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try String(contentsOf: outside, encoding: .utf8) == "fixture")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: base.path)
        #expect(remaining == ["downloads"])
    }

    @Test func replacedCacheLinkAndLinksOutsideCacheArePreserved() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let outside = try write("Documents/valuable", in: home)
        _ = try write("Library/Caches/Homebrew/seed", in: home)
        _ = try write("Library/Logs/seed", in: home)
        let link = home.appendingPathComponent("Library/Caches/Homebrew/Current")
        let logLink = home.appendingPathComponent("Library/Logs/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: logLink, withDestinationURL: outside)
        let engine = CleanerActor(home: home)
        let scan = try await engine.scan()
        try FileManager.default.removeItem(at: link)
        let fresh = try write("Library/Caches/Homebrew/Current/new", in: home)
        let result = try await engine.delete(scan: scan.id, selected: Set(scan.items.map(\.id)), confirmed: true, sensitiveConfirmed: true)
        #expect(result.skippedFiles == 1)
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: logLink.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func runningApplicationsHaveReadableNamesInReport() async throws {
        let home = try fixture(); defer { try? FileManager.default.removeItem(at: home) }
        for folder in ["Code", "com.googlecode.iterm2", "com.google.Chrome"] {
            _ = try write("Library/Caches/" + folder + "/cache", in: home)
        }
        let result = try await CleanerActor(home: home, runningApps: ["com.microsoft.VSCode", "com.googlecode.iterm2", "com.google.Chrome"]).quickClean()
        #expect(result.runningApplications == ["Chrome", "VS Code", "iTerm2"])
        #expect(result.skippedFiles == 3 && result.removedFiles == 0)
    }

    @Test func activeVRAMExcludesReusablePoolAndSystemMemory() {
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": 1500, "vramUsedBytes": 3999,
                                      "allocated_size": 4000, "in_use_sys_mem": 700,
                                      "orphanedReusableVidMemoryBytes": 2499], total: 4096) == 1500)
        #expect(GPUService.activeVRAM(["vramUsedBytes": 3999, "vramFreeBytes": 1], total: 4096) == nil)
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": -1], total: 4096) == nil)
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": 5000], total: 4096) == nil)
        #expect(GPUService.activeVRAM(["inUseVidMemoryBytes": 0], total: 4096) == 0)
    }
}
