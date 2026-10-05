import MonitorCore
import SwiftUI

struct GPUCardContent: View {
    let gpu: GPUMetrics
    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 10) {
            if gpu.isUnified {
                Text(L("Unified VRAM")).font(.headline)
                if let shared = gpu.sharedMemoryTotal {
                    Text(L("Общая RAM: \(MetricFormat.gb(shared)) GB"))
                }
            } else if let used = gpu.usedVRAM, let total = gpu.totalVRAM {
                MetricGauge(title: L("VRAM In-Use"), used: used, total: total)
            } else {
                Text(L("VRAM In-Use")).foregroundStyle(.secondary)
                MemoryAmountView(used: gpu.usedVRAM, total: gpu.totalVRAM)
            }
            if gpu.isUnified, let limit = gpu.workingSetLimit {
                Text(L("Рекомендованный лимит Metal: \(MetricFormat.gb(limit)) GB")).font(.caption)
            }
            Text(L("Load \(MetricFormat.percent(gpu.utilization)) · \(MetricFormat.temperature(gpu.temperature))"))
                .fixedSize(horizontal: false, vertical: true)
            if let issue = gpu.issue { Text(L10n.text(issue)).font(.caption).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
