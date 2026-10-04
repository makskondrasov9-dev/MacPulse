import Foundation
import MonitorCore
import SwiftUI

struct HistoryPoint: Identifiable {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    var id: Date { date }
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var pollingInterval = normalizedInterval(
        UserDefaults.standard.object(forKey: "pollingInterval") as? Double ?? 2
    )

    static func normalizedInterval(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 1), 3) : 2
    }

    func setPollingInterval(_ value: Double) {
        pollingInterval = Self.normalizedInterval(value)
    }

    let cleaner = CleanerModel()
    private let collector = MetricCollector()
    private var polling: Task<Void, Never>?

    func start() {
        guard polling == nil else { return }
        let collector = collector
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await collector.sample()
                guard !Task.isCancelled else { break }
                self?.accept(snapshot)
                do { try await Task.sleep(for: .seconds(self?.pollingInterval ?? 2), tolerance: .milliseconds(200)) }
                catch { break }
            }
            await collector.close()
        }
    }

    func stop() async {
        await cleaner.stop()
        polling?.cancel()
        await polling?.value
        polling = nil
    }

    private func accept(_ snapshot: MonitorSnapshot) {
        self.snapshot = snapshot
        history.append(HistoryPoint(date: snapshot.date, cpu: snapshot.cpu?.usage, gpu: snapshot.gpu.utilization))
        history.removeAll { $0.date < snapshot.date.addingTimeInterval(-60) }
    }
}

enum MetricFormat {
    static func ratio(_ used: UInt64, _ total: UInt64) -> Double? {
        guard total > 0 else { return nil }
        return min(Double(used) / Double(total) * 100, 100)
    }
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    static func temperature(_ value: Double?) -> String { value.map { String(format: "%.0f °C", $0) } ?? "—" }
    // Binary units match the hardware profile (32 GB RAM / 4 GB VRAM).
    static func gb(_ value: UInt64) -> String { String(format: "%.1f", Double(value) / 1_073_741_824) }
    static func uptime(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        let minutes = Int(value) / 60
        return "\(minutes / 1440)d \(minutes / 60 % 24)h \(minutes % 60)m"
    }
}
