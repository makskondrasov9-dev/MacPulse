import MonitorCore
import SwiftUI

struct NetworkCardContent: View {
    let network: NetworkMetrics
    @ObservedObject var diagnostics: DiagnosticsModel
    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 8) {
            Text(network.isAvailable ? (network.interfaces.isEmpty ? L("Нет подключения") : network.interfaces.joined(separator: " · ")) : L("Данные недоступны"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            reading(L("Загрузка"), symbol: "↓", value: ByteSizeFormat.rate(network.downloadBytesPerSecond))
            reading(L("Отправка"), symbol: "↑", value: ByteSizeFormat.rate(network.uploadBytesPerSecond))
            NetworkIdentitySummary(model: diagnostics)
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

/// Observes identity changes directly, independently of the metric polling loop.
struct NetworkIdentitySummary: View {
    @ObservedObject var model: DiagnosticsModel
    @AppStorage("hideUnavailableMetrics") private var hideUnavailable = true
    private var network: NetworkPresentation { NetworkPresentation(model.interfaces) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if network.localIP != nil || !hideUnavailable { Text(L("Local IP") + ": " + (network.localIP ?? "—")).textSelection(.enabled) }
            if model.publicIPEnabled {
                if model.publicIP != nil || !hideUnavailable { Text(L("Public IP") + ": " + (model.publicIP ?? "—")).textSelection(.enabled) }
            } else {
                Button(L("Enable public IP")) { model.publicIPEnabled = true }
                    .help(L("The configured service receives your public IP. History stays on this Mac (up to 200 changes). Configure the URL and interval in Settings."))
            }
            Label(network.hasTunnel ? L("Tunnel detected") : L("No tunnel detected"), systemImage: network.hasTunnel ? "network.badge.shield.half.filled" : "network")
                .help(L("VPN detection is based on tunnel interfaces with an assigned IP; it does not guarantee traffic protection."))
            if let ip = network.tunnelIP { Text("VPN IP: " + ip).textSelection(.enabled) }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
