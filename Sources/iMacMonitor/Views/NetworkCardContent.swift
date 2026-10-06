import MonitorCore
import SwiftUI

struct NetworkCardContent: View {
    let network: NetworkMetrics
    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 8) {
            Text(network.isAvailable ? (network.interfaces.isEmpty ? L("Нет подключения") : network.interfaces.joined(separator: " · ")) : L("Данные недоступны"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            reading(L("Загрузка"), symbol: "↓", value: ByteSizeFormat.rate(network.downloadBytesPerSecond))
            reading(L("Отправка"), symbol: "↑", value: ByteSizeFormat.rate(network.uploadBytesPerSecond))
            Divider()
            Text(L("За сессию")).font(.caption).foregroundStyle(.secondary)
            reading(L("Получено"), symbol: "↓", value: ByteSizeFormat.string(network.receivedBytes))
            reading(L("Отправлено"), symbol: "↑", value: ByteSizeFormat.string(network.sentBytes))
        }
        .help(L("Трафик физических интерфейсов, включая локальную сеть. Счётчики сессии обнуляются при перезапуске приложения."))
    }

    private func reading(_ title: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(symbol) \(value)").monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .combine)
    }
}
