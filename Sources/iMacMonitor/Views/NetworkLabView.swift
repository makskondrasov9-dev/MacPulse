import Charts
import MonitorCore
import SwiftUI

struct NetworkLabView: View {
    @ObservedObject var model: DiagnosticsModel
    @Binding var host: String
    let start: (DiagnosticsModel.Test) -> Void
    var body: some View {
        GroupBox(L("Network Lab")) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L("Host or IP address"), text: $host).textFieldStyle(.roundedBorder)
                HStack {
                    Button(L("Traceroute")) { start(.trace) }.disabled(!NetworkLab.validHost(host))
                    Button(L("IPv6 check")) { start(.ipv6) }
                }.disabled(model.running != nil)
                ForEach(model.hops) { hop in
                    HStack {
                        Text(String(hop.number)).frame(width: 30, alignment: .leading)
                        Text(hop.address ?? "*").textSelection(.enabled)
                        Spacer()
                        Text(hop.milliseconds.isEmpty ? L("No reply") : hop.milliseconds.map { String(format: "%.2f ms", $0) }.joined(separator: " · "))
                    }.font(.callout.monospacedDigit())
                }
                if let report = model.ipv6 {
                    LabeledContent("IPv6", value: report.addresses.isEmpty ? L("No IPv6 address") : report.addresses.joined(separator: " · "))
                    LabeledContent(L("Gateway"), value: report.gateway ?? L("No IPv6 default route"))
                    if report.gateway != nil { Text(report.gatewayResponded == true ? L("Gateway replied") : L("No ICMP reply; IPv6 may still work")) }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NetworkTransferView: View {
    @ObservedObject var model: DiagnosticsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.networkTargets.isEmpty {
                Text(L("Network test endpoints")).font(.headline)
                ForEach(model.networkTargets, id: \.self) { Text($0).font(.caption).textSelection(.enabled).lineLimit(3) }
                if model.running == .network { Text(model.probingLatency ? L("HTTP probe in progress") : L("Measuring network traffic")) }
            }
            if let last = model.transfers.last {
                HStack {
                    Text("↓ " + number(last.download, unit: "Mbps"))
                    Text("↑ " + number(last.upload, unit: "Mbps"))
                    Text(L("HTTP latency") + ": " + number(model.httpLatency, unit: "ms"))
                }.monospacedDigit()
                Chart(model.transfers) { point in
                    if let value = point.download { LineMark(x: .value("Time", point.date), y: .value("Mbps", value)).foregroundStyle(by: .value("Direction", "↓")) }
                    if let value = point.upload { LineMark(x: .value("Time", point.date), y: .value("Mbps", value)).foregroundStyle(by: .value("Direction", "↑")) }
                }.frame(height: 130).padding(.vertical, 8).drawingGroup()
                Chart(model.transfers) { point in
                    if let value = point.latency { LineMark(x: .value("Time", point.date), y: .value("ms", value)).foregroundStyle(.orange) }
                }.frame(height: 80).padding(.vertical, 8).drawingGroup()
                Text(L("Live traffic includes other apps. HTTP latency includes connection setup; final networkQuality results appear after completion."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func number(_ value: Double?, unit: String) -> String { value.map { String(format: "%.1f", locale: L10n.locale, $0) + " " + unit } ?? "—" }
}

struct CPUTelemetryView: View {
    @ObservedObject var model: DiagnosticsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(L("Current CPU frequency"), value: L("Unavailable via public API"))
            if let frequency = model.nominalGHz {
                LabeledContent(L("Nominal frequency"), value: String(format: "%.2f GHz", frequency))
            }
            if let point = model.thermal.last {
                if let temperature = point.temperature { LabeledContent(L("Температура CPU"), value: MetricFormat.temperature(temperature)) }
                LabeledContent(L("Thermal throttling indicators"), value: model.currentThermalPressure ? L("Detected") : L("Not detected"))
                if let limit = point.speedLimit { LabeledContent(L("CPU speed limit"), value: MetricFormat.percent(limit)) }
            }
            if let percent = model.performancePercent {
                ProgressView(value: percent, total: 100) { Text(L("Performance vs best measured on this Mac") + ": " + MetricFormat.percent(percent)) }
            }
            Text(L("Reference: same workload and thread count on this Mac, not a theoretical model maximum. Power limits can have non-thermal causes."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
