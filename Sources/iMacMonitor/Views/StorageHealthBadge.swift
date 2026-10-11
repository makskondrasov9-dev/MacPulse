import MonitorCore
import SwiftUI

struct StorageHealthBadge: View {
    let health: StorageHealth
    @Environment(\.locale) private var locale
    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 4) {
            if let status = health.status {
                Label(status == .passed ? L("SMART: исправен") : L("SMART: предупреждение"),
                      systemImage: status == .passed ? "checkmark.shield" : "exclamationmark.triangle")
                    .foregroundStyle(status == .passed ? Color.green : Color.orange)
            }
            if let life = health.lifeRemaining { Text(L("Ресурс SSD: \(MetricFormat.percent(life))")) }
            if let tb = health.terabytesWritten { Text(L("Записано: \(tb, specifier: "%.2f") ТБ")) }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
            .help(health.model)
    }
}
