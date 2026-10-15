import Foundation
import CoreServices
import Security

public enum ApplicationSignature: String, Sendable {
    case trusted = "Apple / Developer ID", selfSigned = "Self-Signed / Ad-Hoc"
    case unsigned = "Unsigned", invalid = "Invalid signature", unavailable = "Signature unavailable"
}

public enum CodeSignatureVerifier {
    public static func inspect(_ url: URL) -> ApplicationSignature {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        if creation == errSecCSUnsigned { return .unsigned }
        guard creation == errSecSuccess, let code else { return .unavailable }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        if status == errSecCSUnsigned { return .unsigned }
        guard status == errSecSuccess else { return .invalid }
        var requirement: SecRequirement?
        let expression = "anchor apple or (anchor apple generic and (certificate leaf[field.1.2.840.113635.100.6.1.13] exists or certificate leaf[field.1.2.840.113635.100.6.1.9] exists))"
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return .unavailable }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess ? .trusted : .selfSigned
    }
}

public struct ApplicationMetadata: Sendable {
    public let bytes: UInt64?
    public let lastUsed: Date?
    public let usesModificationDate: Bool
    public let signature: ApplicationSignature
    public init(bytes: UInt64?, spotlight: Date?, modification: Date?, signature: ApplicationSignature) {
        self.bytes = bytes; lastUsed = spotlight ?? modification
        usesModificationDate = spotlight == nil && modification != nil
        self.signature = signature
    }
}

/// Metadata is informational and never participates in deletion authorization.
public actor ApplicationMetadataService {
    public init() {}
    public func read(_ url: URL) throws -> ApplicationMetadata {
        try Task.checkCancellation()
        let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL)
        let lastUsed = item.flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var size: UInt64 = 0
        var complete = true
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], errorHandler: { _, _ in complete = false; return false }) {
            for case let child as URL in enumerator {
                try Task.checkCancellation()
                guard let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else { complete = false; continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { size += UInt64(max(0, values.fileSize ?? 0)) }
            }
        } else { complete = false }
        let signature = CodeSignatureVerifier.inspect(url)
        try Task.checkCancellation()
        return ApplicationMetadata(bytes: complete ? size : nil, spotlight: lastUsed, modification: modified, signature: signature)
    }
}

public enum ApplicationSort: String, CaseIterable, Sendable { case size = "Size", name = "Name", lastUsed = "Last used" }
public enum ApplicationFilter: String, CaseIterable, Sendable { case all = "All applications", old = "Unused for 3 months", unsigned = "Unsigned" }
public enum ApplicationOrdering {
    public static func list(_ apps: [InstalledApplication], metadata: [String: ApplicationMetadata], sort: ApplicationSort, filter: ApplicationFilter, now: Date = Date()) -> [InstalledApplication] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now
        return apps.filter { app in
            switch filter {
            case .all: true
            case .old: metadata[app.id]?.lastUsed.map { $0 < cutoff } ?? false
            case .unsigned: metadata[app.id]?.signature == .unsigned
            }
        }.sorted { a, b in
            switch sort {
            case .size:
                let x = metadata[a.id]?.bytes, y = metadata[b.id]?.bytes
                if x != y { return (x ?? 0) > (y ?? 0) || (x != nil && y == nil) }
            case .lastUsed:
                let x = metadata[a.id]?.lastUsed ?? .distantPast, y = metadata[b.id]?.lastUsed ?? .distantPast
                if x != y { return x > y }
            case .name: break
            }
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.id < b.id : comparison == .orderedAscending
        }
    }
}
