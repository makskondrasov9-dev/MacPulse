import Foundation

struct StorageService {
    func sample() -> StorageMetrics? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attrs[.systemSize] as? NSNumber)?.uint64Value,
              let free = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value,
              total > 0 else { return nil }
        return StorageMetrics(total: total, free: free)
    }
}
