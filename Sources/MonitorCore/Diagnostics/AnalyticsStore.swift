import Foundation

public struct SessionPeaks: Codable, Sendable {
    public private(set) var cpuTemperature: Double?
    public private(set) var memoryBytes: UInt64 = 0
    public private(set) var gpuLoad: Double?
    public init() {}
    public mutating func record(temperature: Double?, memory: UInt64?, gpu: Double?) {
        if let t = temperature, t.isFinite, (0...150).contains(t) { cpuTemperature = max(cpuTemperature ?? t, t) }
        if let memory { memoryBytes = max(memoryBytes, memory) }
        if let gpu, gpu.isFinite, (0...100).contains(gpu) { gpuLoad = max(gpuLoad ?? gpu, gpu) }
    }
}

public struct UsageEntry: Codable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var seconds: Double
}

public struct DailyUsage: Codable, Sendable {
    public private(set) var day: Date
    public private(set) var entries: [String: UsageEntry] = [:]
    public init(now: Date = Date(), calendar: Calendar = .current) { day = calendar.startOfDay(for: now) }
    public mutating func record(id: String, name: String, from start: Date, to end: Date, calendar: Calendar = .current) {
        let newDay = calendar.startOfDay(for: end)
        if day != newDay { day = newDay; entries = [:] }
        let seconds = end.timeIntervalSince(max(start, newDay))
        // Poll gaps/sleep do not count as foreground usage.
        guard seconds > 0, seconds <= 10 else { return }
        var entry = entries[id] ?? UsageEntry(id: id, name: name, seconds: 0)
        entry.name = name; entry.seconds += seconds; entries[id] = entry
    }
    public mutating func resetDay(at now: Date = Date(), calendar: Calendar = .current) {
        let next = calendar.startOfDay(for: now)
        if next != day { day = next; entries = [:] }
    }
    public var top: [UsageEntry] { Array(entries.values.sorted { $0.seconds > $1.seconds }.prefix(5)) }
}

public struct ProcessAudit: Sendable {
    public private(set) var entries: [String: UsageEntry] = [:]
    public init() {}
    public mutating func record(_ processes: [ProcessMetrics], elapsed: TimeInterval) {
        guard elapsed > 0, elapsed <= 10 else { return }
        for process in processes {
            guard let cpu = process.cpu, cpu.isFinite, cpu >= 0 else { continue }
            let key = process.executablePath.isEmpty ? process.name : process.executablePath
            var entry = entries[key] ?? UsageEntry(id: key, name: process.name, seconds: 0)
            entry.seconds += cpu / 100 * elapsed
            entries[key] = entry
        }
        if entries.count > 2048 { entries = Dictionary(uniqueKeysWithValues: entries.values.sorted { $0.seconds > $1.seconds }.prefix(1024).map { ($0.id, $0) }) }
    }
    public var top: [UsageEntry] { Array(entries.values.sorted { $0.seconds > $1.seconds }.prefix(5)) }
}

/// Serialized, bounded local state. No window titles, document paths or browsing history.
public actor AnalyticsStore {
    private let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacPulse/Analytics")
    }
    public func load<T: Decodable & Sendable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)), data.count < 2_000_000 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    public func save<T: Encodable & Sendable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
