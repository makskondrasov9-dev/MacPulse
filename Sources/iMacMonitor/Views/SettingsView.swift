import MonitorCore
import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: MonitorModel
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBarIcon") private var showIcon = true
    @AppStorage("showCPUPercentage") private var showCPU = true
    @AppStorage("showRAMPercentage") private var showRAM = false
    @AppStorage("showGPUPercentage") private var showGPU = false
    @AppStorage("showCPUTemperature") private var showTemperature = false
    @AppStorage("menuBarGPUUsesVRAM") private var gpuUsesVRAM = false
    @AppStorage("menuBarTextStyle") private var menuBarStyle = "full"
    @AppStorage("showCPUChart") private var showCPUChart = true
    @AppStorage("showNetworkChart") private var showNetworkChart = false
    @AppStorage("showNetworkSpeed") private var showNetwork = false
    @StateObject private var loginItem = LoginItemService()
    @AppStorage("pollingInterval") private var pollingInterval = 2.0
    @State private var access: DiskAccessProbe.Status = .unknown
    @State private var checkingAccess = false
    @State private var settingsError: String?
    private let probe = DiskAccessProbe()

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        Form {
            Section(L("Язык")) {
                Picker(L("Язык приложения"), selection: $language) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.nativeName).tag(item.rawValue)
                    }
                }
                Text(L("Язык меняется сразу. Названия процессов и пути к файлам сохраняются в оригинале."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Автозапуск")) {
                Toggle(L("Запускать при входе в систему"), isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                ))
                .disabled(loginItem.isUpdating)
                if loginItem.status == .requiresApproval {
                    Text(L("Разрешите автозапуск MacPulse в Системных настройках."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("Открыть настройки автозапуска")) { loginItem.openSettings() }
                }
                if loginItem.status == .notFound {
                    Text(L("Для автозапуска переместите MacPulse в «Программы» и запустите оттуда."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = loginItem.errorMessage {
                    Text(L("Не удалось изменить автозапуск: \(error)"))
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section(L("Оформление")) {
                Picker(L("Тема"), selection: $appearance) {
                    Text(L("Как в системе")).tag("system")
                    Text(L("Светлая")).tag("light")
                    Text(L("Тёмная")).tag("dark")
                }
            }
            Section(L("Строка меню")) {
                Picker(L("Стиль текста"), selection: Binding(get: { MenuBarDisplayMode.resolve(menuBarStyle).rawValue }, set: { menuBarStyle = $0 })) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
                if MenuBarDisplayMode.resolve(menuBarStyle).hasChart {
                    Toggle(L("График CPU"), isOn: $showCPUChart)
                    Toggle(L("График сети"), isOn: $showNetworkChart)
                    Text(L("Сеть: сумма загрузки и отправки, масштаб по последним 12 замерам."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("Показывать иконку"), isOn: $showIcon)
                Toggle(L("Процент CPU"), isOn: $showCPU)
                Toggle(L("Процент RAM"), isOn: $showRAM)
                Toggle(L("Процент GPU / VRAM"), isOn: $showGPU)
                if showGPU {
                    Picker(L("Показатель GPU"), selection: $gpuUsesVRAM) {
                        Text(L("Загрузка GPU")).tag(false)
                        Text(L("Занятая VRAM")).tag(true)
                    }
                }
                Toggle(L("Температура CPU"), isOn: $showTemperature)
                Toggle(L("Скорость сети"), isOn: $showNetwork)
                NetworkIdentitySettings(model: model.diagnostics)
                LabeledContent(L("Предпросмотр")) { MenuBarLabel(model: model) }
                Text(L("Если отключить все элементы, значок останется, чтобы меню было доступно."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Обновление метрик")) {
                Slider(value: $pollingInterval, in: 1...3, step: 0.5) {
                    Text(L("Интервал: \(pollingInterval, specifier: "%.1f") с"))
                } minimumValueLabel: { Text(L("1 с")) } maximumValueLabel: { Text(L("3 с")) }
                Text(L("Рекомендуется 1,5–2 секунды. Новый интервал применяется со следующего цикла."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Полный доступ к диску")) {
                Label(L10n.text(access.rawValue), systemImage: access == .readable ? "checkmark.shield" : "lock.shield")
                    .foregroundStyle(access == .readable ? Color.green : Color.secondary)
                Text(L("Проверка чтения защищённого файла — косвенный признак доступа. Точный статус смотрите в Системных настройках. Для мониторинга метрик полный доступ не требуется."))
                    .font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { accessButtons }
                    VStack(alignment: .leading) { accessButtons }
                }
                if let settingsError { Text(settingsError).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onInitialChange(of: pollingInterval) { value in
            let normalized = MonitorModel.normalizedInterval(value)
            if value != normalized { pollingInterval = normalized }
            model.setPollingInterval(normalized)
        }
        .task { loginItem.refresh(); await checkAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
            Task { await checkAccess() }
        }
    }

    @ViewBuilder private var accessButtons: some View {
        Button(checkingAccess ? L("Проверка…") : L("Проверить доступ")) { Task { await checkAccess() } }
            .disabled(checkingAccess)
        Button(L("Открыть Системные настройки")) { openPrivacySettings() }
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
            settingsError = L("Откройте Конфиденциальность и безопасность → Полный доступ к диску вручную.")
            return
        }
        settingsError = nil
    }
}


private struct NetworkIdentitySettings: View {
    @ObservedObject var model: DiagnosticsModel
    @AppStorage("showMenuBarIP") private var showIP = false
    @AppStorage("showMenuBarVPN") private var showVPN = false
    @AppStorage("menuBarIPSource") private var ipSource = "local"
    @AppStorage("hideUnavailableMetrics") private var hideUnavailable = true
    var body: some View {
        Toggle(L("IP in menu bar"), isOn: $showIP)
        if showIP {
            Picker(L("IP source"), selection: $ipSource) {
                Text(L("Local IP")).tag("local")
                Text(L("Public IP")).tag("public")
            }
            if ipSource == "public" {
                Toggle(L("Public IP history (ipify)"), isOn: $model.publicIPEnabled)
                Text(L("Public IP lookup uses ipify. Enable it to check every 60 seconds.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        Toggle(L("VPN indicator in menu bar"), isOn: $showVPN)
        Text(L("VPN detection is based on tunnel interfaces with an assigned IP; it does not guarantee traffic protection.")).font(.caption).foregroundStyle(.secondary)
        Toggle(L("Hide unavailable values"), isOn: $hideUnavailable)
    }
}
