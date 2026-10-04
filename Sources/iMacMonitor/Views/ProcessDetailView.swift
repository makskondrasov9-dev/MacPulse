import AppKit
import MonitorCore
import SwiftUI

struct ProcessDetailView: View {
    let process: ProcessMetrics
    let requestTermination: () -> Void
    @Environment(\.dismiss) private var dismiss

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: process.isSystem ? "gearshape.2" : "app")
                    .font(.largeTitle).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.name).font(.title2.bold()).textSelection(.enabled)
                    Text(L10n.text(ProcessControlService.description(for: process)))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow { Text("PID"); Text(String(process.pid)) }
                GridRow { Text("CPU"); Text(MetricFormat.percent(process.cpu)) }
                GridRow { Text("RAM"); Text("\(MetricFormat.gb(process.residentBytes)) GB") }
                GridRow { Text(L("Владелец (UID)")); Text(String(process.ownerUID)) }
            }.monospacedDigit()
            Text(L("Исполняемый файл")).font(.headline)
            Text(process.executablePath.isEmpty ? "—" : process.executablePath)
                .font(.caption.monospaced()).textSelection(.enabled)
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .leftToRight)
            Text(L("Показатели зафиксированы в момент открытия. Назначение неизвестного процесса нельзя достоверно определить только по имени."))
                .font(.caption).foregroundStyle(.secondary)
            if !ProcessControlService.canTerminate(process) {
                Label(L("Этот процесс защищён от завершения."), systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Закрыть")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Завершить процесс"), role: .destructive) { requestTermination() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!ProcessControlService.canTerminate(process))
            }
        }.padding(24).frame(minWidth: 440, idealWidth: 560, maxWidth: 660)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
