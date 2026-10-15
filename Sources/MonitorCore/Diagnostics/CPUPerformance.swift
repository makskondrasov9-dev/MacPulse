import Darwin
import Foundation

public struct CPUProgress: Sendable {
    public let elapsed: Double
    public let batches: UInt64
    public let batchesPerSecond: Double
}

actor CPUProgressAccumulator {
    private var counts: [UInt64]
    private let start = ProcessInfo.processInfo.systemUptime
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var previousCount: UInt64 = 0
    init(workers: Int) { counts = Array(repeating: 0, count: workers) }
    func record(worker: Int, count: UInt64) -> CPUProgress? {
        counts[worker] = count
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - previousTime
        guard elapsed >= 1 else { return nil }
        let total = counts.reduce(0, +)
        let sample = CPUProgress(elapsed: now - start, batches: total, batchesPerSecond: Double(total - previousCount) / elapsed)
        previousTime = now; previousCount = total
        return sample
    }
}

/// Same workload and worker count on this Mac; never a fabricated model-wide benchmark.
public struct CPUPerformanceReference: Sendable {
    public private(set) var best: Double
    public init(best: Double = 0) { self.best = best.isFinite && best > 0 ? best : 0 }
    public mutating func record(_ rate: Double) -> Double? {
        guard rate.isFinite, rate > 0 else { return nil }
        best = max(best, rate)
        return min(100, rate / best * 100)
    }
}

public enum CPUCapabilities {
    public static var maximumWorkers: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }
    /// hw.cpufrequency is an OS-reported nominal value, NOT an instantaneous core clock.
    public static var nominalGHz: Double? {
        var value: UInt64 = 0, size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.cpufrequency", &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Double(value) / 1e9
    }
}
