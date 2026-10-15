import Foundation
import Testing
@testable import MonitorCore

struct ReleaseAndMetadataTests {
    @Test func versionsCompareNumerically() throws {
        #expect(try #require(ReleaseVersion("v0.10.0")) > #require(ReleaseVersion("0.9.10")))
        #expect(ReleaseVersion("v0.9.1") == ReleaseVersion("0.9.1"))
        for value in ["0.9", "01.9.1", "0.9.1-beta", "0.-1.0", "0.9.1/../x", "99999999999999999999999.1.0"] {
            #expect(ReleaseVersion(value) == nil)
        }
    }
    private func response(tag: String = "v0.9.2", host: String = "github.com", prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "published_at": "2026-10-14T12:00:00Z", "body": "## New\n- Metadata", "draft": false, "prerelease": prerelease, "assets": [["name": "MacPulse.dmg", "browser_download_url": "https://\(host)/makskondrasov9-dev/MacPulse/releases/download/\(tag)/MacPulse.dmg"]]])
    }
    @Test func releaseParser() throws {
        let release = try ReleaseUpdater.parse(response())
        #expect(release.tag == "v0.9.2")
        #expect(release.notes.contains("Metadata"))
        #expect(throws: (any Error).self) { try ReleaseUpdater.parse(response(host: "example.com")) }
        #expect(throws: (any Error).self) { try ReleaseUpdater.parse(response(prerelease: true)) }
        #expect(throws: (any Error).self) { try ReleaseUpdater.parse(Data("{}".utf8)) }
    }
    @Test func metadataFallbackAndOrdering() {
        let now = Date(), older = now.addingTimeInterval(-200 * 86400)
        let a = InstalledApplication(url: URL(fileURLWithPath: "/A.app"), name: "A", bundleID: "org.a", version: "1", architecture: "Intel")
        let b = InstalledApplication(url: URL(fileURLWithPath: "/B.app"), name: "B", bundleID: "org.b", version: "1", architecture: "Intel")
        let meta = [a.id: ApplicationMetadata(bytes: 10, spotlight: older, modification: now, signature: .unsigned), b.id: ApplicationMetadata(bytes: 20, spotlight: nil, modification: now, signature: .selfSigned)]
        #expect(meta[a.id]?.lastUsed == older)
        #expect(meta[b.id]?.usesModificationDate == true)
        #expect(ApplicationOrdering.list([a,b], metadata: meta, sort: .size, filter: .all).map(\.id) == [b.id,a.id])
        #expect(ApplicationOrdering.list([b,a], metadata: meta, sort: .name, filter: .all).map(\.id) == [a.id,b.id])
        #expect(ApplicationOrdering.list([a,b], metadata: meta, sort: .lastUsed, filter: .all).first?.id == b.id)
        #expect(ApplicationOrdering.list([a,b], metadata: meta, sort: .size, filter: .old, now: now).map(\.id) == [a.id])
        #expect(ApplicationOrdering.list([a,b], metadata: meta, sort: .size, filter: .unsigned).map(\.id) == [a.id])
        #expect(ApplicationOrdering.list([a,b], metadata: [:], sort: .size, filter: .old).isEmpty)
    }
    @Test func realSignatures() throws {
        let system = URL(fileURLWithPath: "/usr/bin/true")
        #expect(CodeSignatureVerifier.inspect(system) == .trusted)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("test-code")
        try FileManager.default.copyItem(at: system, to: file)
        func codesign(_ arguments: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = arguments + [file.path]; try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        try codesign(["--force", "--sign", "-"])
        #expect(CodeSignatureVerifier.inspect(file) == .selfSigned)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 4096)
        try handle.write(contentsOf: Data([0xff, 0xff, 0xff, 0xff]))
        try handle.close()
        #expect(CodeSignatureVerifier.inspect(file) == .invalid)
        try codesign(["--remove-signature"])
        #expect(CodeSignatureVerifier.inspect(file) == .unsigned)
        #expect(CodeSignatureVerifier.inspect(folder.appendingPathComponent("absent")) == .unavailable)
    }
    @Test func metadataCancellation() async {
        let task = Task { try Task.checkCancellation(); return try await ApplicationMetadataService().read(URL(fileURLWithPath: "/Applications")) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
    }
}
