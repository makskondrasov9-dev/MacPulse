import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MonitorModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBarIcon") private var showIcon = true
    @AppStorage("showCPUPercentage") private var showCPU = true
    @AppStorage("showRAMPercentage") private var showRAM = false
    @AppStorage("showGPUPercentage") private var showGPU = false
    @AppStorage("showCPUTemperature") private var showTemperature = false
    @AppStorage("menuBarGPUUsesVRAM") private var gpuUsesVRAM = false
    @AppStorage("pollingInterval") private var pollingInterval = 2.0
    @State private var access: DiskAccessProbe.Status = .unknown
    @State private var checkingAccess = false
    @State private var settingsError: String?
    private let probe = DiskAccessProbe()

    var body: some View {
        Form {
            Section("Оформление") {
                Picker("Тема", selection: $appearance) {
                    Text("Как в системе").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
            }
            Section("Строка меню") {
                Toggle("Показывать иконку", isOn: $showIcon)
                Toggle("Процент CPU", isOn: $showCPU)
                Toggle("Процент RAM", isOn: $showRAM)
                Toggle("Процент GPU / VRAM", isOn: $showGPU)
                if showGPU {
                    Picker("Показатель GPU", selection: $gpuUsesVRAM) {
                        Text("Загрузка GPU").tag(false)
                        Text("Занятая VRAM").tag(true)
                    }
                }
                Toggle("Температура CPU", isOn: $showTemperature)
                LabeledContent("Предпросмотр") { MenuBarLabel(model: model) }
                Text("Если отключить все элементы, значок останется, чтобы меню было доступно.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Обновление метрик") {
                Slider(value: $pollingInterval, in: 1...3, step: 0.5) {
                    Text("Интервал: \(pollingInterval, specifier: "%.1f") с")
                } minimumValueLabel: { Text("1 с") } maximumValueLabel: { Text("3 с") }
                Text("Рекомендуется 1,5–2 секунды. Новый интервал применяется со следующего цикла.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Полный доступ к диску") {
                Label(access.rawValue, systemImage: access == .readable ? "checkmark.shield" : "lock.shield")
                    .foregroundStyle(access == .readable ? Color.green : Color.secondary)
                Text("Проверка чтения защищённого файла — косвенный признак доступа. Точный статус смотрите в Системных настройках. Для мониторинга метрик полный доступ не требуется.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(checkingAccess ? "Проверка…" : "Проверить доступ") { Task { await checkAccess() } }
                        .disabled(checkingAccess)
                    Button("Открыть Системные настройки") { openPrivacySettings() }
                }
                if let settingsError { Text(settingsError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: pollingInterval, initial: true) { _, value in
            let normalized = MonitorModel.normalizedInterval(value)
            if value != normalized { pollingInterval = normalized }
            model.setPollingInterval(normalized)
        }
        .task { await checkAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkAccess() }
        }
    }

    private func checkAccess() async {
        guard !checkingAccess else { return }
        checkingAccess = true
        access = await probe.check()
        checkingAccess = false
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
              NSWorkspace.shared.open(url) else {
            settingsError = "Откройте Конфиденциальность и безопасность → Полный доступ к диску вручную."
            return
        }
        settingsError = nil
    }
}
