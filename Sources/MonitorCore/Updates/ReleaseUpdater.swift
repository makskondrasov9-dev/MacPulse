import Foundation

public struct ReleaseVersion: Comparable, Sendable {
    public let components: [UInt64]
    public init?(_ text: String) {
        let raw = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              pieces.allSatisfy({ $0.count == 1 || $0.first != "0" }) else { return nil }
        let values = pieces.compactMap { UInt64($0) }
        guard values.count == 3 else { return nil }
        components = values
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct AvailableRelease: Sendable {
    public let version: ReleaseVersion
    public let tag: String
    public let date: Date
    public let notes: String
    public let download: URL
}

public enum ReleaseUpdater {
    public static let developmentVersion = "1.0.1"
    public static let endpoint = URL(string: "https://api.github.com/repos/makskondrasov9-dev/MacPulse/releases/latest")!
    public static func latest() async throws -> AvailableRelease {
        let data = try await DiagnosticHTTP.fetch(endpoint, maximumBytes: 2_000_000, headers: ["Accept": "application/vnd.github+json", "User-Agent": "MacPulse"])
        return try parse(data)
    }
    public static func parse(_ data: Data) throws -> AvailableRelease {
        struct Response: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String; let published_at: Date; let body: String?
            let draft: Bool; let prerelease: Bool; let assets: [Asset]
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(Response.self, from: data)
        guard !dto.draft, !dto.prerelease, let version = ReleaseVersion(dto.tag_name),
              let asset = dto.assets.first(where: { $0.name == "MacPulse.dmg" }),
              asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil, asset.browser_download_url.password == nil,
              asset.browser_download_url.path == "/makskondrasov9-dev/MacPulse/releases/download/\(dto.tag_name)/MacPulse.dmg" else {
            throw DiagnosticError.failed("Invalid release response")
        }
        return AvailableRelease(version: version, tag: dto.tag_name, date: dto.published_at, notes: String((dto.body ?? "").prefix(50_000)), download: asset.browser_download_url)
    }
}
