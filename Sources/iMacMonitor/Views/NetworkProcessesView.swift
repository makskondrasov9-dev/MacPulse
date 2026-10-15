import AppKit
import MonitorCore
import SwiftUI

@MainActor final class NetworkProcessModel: ObservableObject {
    @Published var rows: [ProcessConnection] = []
    @Published var error = false
    @Published var refreshing = false
    private let service = NetworkProcessMonitorService()
    func observe() async {
        while !Task.isCancelled {
            refreshing = true
            do { let next = try await service.sample(); try Task.checkCancellation(); rows = next; error = false }
            catch { if !Task.isCancelled { rows = []; self.error = true } }
            refreshing = false
            do { try await Task.sleep(for: .seconds(3)) } catch { break }
        }
    }
}

struct NetworkProcessesView: View {
    @StateObject private var model = NetworkProcessModel()
    @State private var query = ""
    @State private var remoteOnly = true
    private var rows: [ProcessConnection] { model.rows.filter { $0.matches(query) && (!remoteOnly || $0.isActiveRemote) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Process network activity")).font(.title2.bold())
            Text(L("Visible TCP/UDP sockets, refreshed every 3 seconds. Access is limited by macOS permissions. A connection does not prove data transfer."))
                .font(.caption).foregroundStyle(.secondary)
            TextField(L("Search app or port"), text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Toggle(L("Remote connections only"), isOn: $remoteOnly)
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
            }
            if model.error { Text(L("Unable to read process connections")).foregroundStyle(.secondary) }
            Table(rows) {
                TableColumn(L("Приложение")) { row in
                    HStack {
                        if let app = NSRunningApplication(processIdentifier: row.pid), let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(row.process + " (\(row.pid))").lineLimit(1)
                    }.help(row.process)
                }.width(min: 140, ideal: 190)
                TableColumn(L("Remote address")) { row in Text(row.remote ?? "—").textSelection(.enabled) }.width(min: 150, ideal: 240)
                TableColumn(L("Local address")) { row in Text(row.local).textSelection(.enabled) }.width(min: 120, ideal: 180)
                TableColumn(L("Protocol"), value: \.transport).width(65)
                TableColumn(L("Status"), value: \.state).width(min: 90, ideal: 120)
            }
            if rows.isEmpty && !model.refreshing && !model.error { Text(L("No matching connections")).foregroundStyle(.secondary) }
        }.padding(20).task { await model.observe() }
    }
}
