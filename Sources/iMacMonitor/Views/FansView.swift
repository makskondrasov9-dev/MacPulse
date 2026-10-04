import MonitorCore
import SwiftUI

struct FansView: View {
    @ObservedObject var model: FanModel
    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Вентиляторы")).font(.largeTitle.bold())
                Text(L("Задайте минимальные обороты или плавное повышение при нагреве. macOS может увеличить обороты выше выбранных — защита от перегрева остаётся включённой."))
                    .foregroundStyle(.secondary)
                Label(L10n.text(model.status), systemImage: model.active ? "fan.fill" : "shield.checkered")
                if let error = model.error { Text(L10n.text(error)).foregroundStyle(.orange).textSelection(.enabled) }
                Button(L("Вернуть все вентиляторы в автоматический режим")) { Task { await model.stopSession() } }
                    .disabled(!model.active && !model.authorizing)
                ForEach(model.fans) { fan in
                    FanConfigurationView(fan: fan, minimum: model.hardwareMinimum[fan.id] ?? fan.minimum, model: model)
                }
                Text(L("Пользовательский режим действует только в текущей сессии. При выходе, сне или потере связи помощник восстанавливает исходные минимальные обороты. После перезапуска применяется автоматика. Не запускайте одновременно другие программы управления вентиляторами."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct FanConfigurationView: View {
    let fan: FanReading
    let minimum: Double
    @ObservedObject var model: FanModel
    @State private var mode: FanMode = .automatic
    @State private var lowerRPM = 1200.0
    @State private var upperRPM = 2700.0
    @State private var start = 50.0
    @State private var full = 80.0
    @State private var sensor: FanSensor = .cpu

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("Вентилятор \(fan.id + 1)"), systemImage: "fan")
                Spacer()
                Text(L("\(fan.rpm, specifier: "%.0f") об/мин")).font(.title2.monospacedDigit())
            }
            Text(L("Диапазон: \(minimum, specifier: "%.0f")–\(fan.maximum, specifier: "%.0f") об/мин"))
                .font(.caption).foregroundStyle(.secondary)
            if fan.controllable {
                Picker(L("Режим"), selection: $mode) {
                    Text(L("Автоматически (macOS)")).tag(FanMode.automatic)
                    Text(L("Минимальные обороты")).tag(FanMode.minimum)
                    Text(L("По температуре")).tag(FanMode.temperature)
                }
                if mode != .automatic {
                    Text(L("Не ниже \(lowerRPM, specifier: "%.0f") об/мин"))
                    Slider(value: $lowerRPM, in: minimum...max(minimum + 1, fan.maximum), step: 50)
                }
                if mode == .temperature {
                    Picker(L("Датчик"), selection: $sensor) {
                        Text("CPU").tag(FanSensor.cpu)
                        Text("GPU").tag(FanSensor.gpu)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(L("Начало: \(start, specifier: "%.0f") °C"), value: $start, in: 30...85)
                        Stepper(L("Верхний предел: \(full, specifier: "%.0f") °C"), value: $full, in: 40...95)
                    }
                    Text(L("При \(full, specifier: "%.0f") °C: \(upperRPM, specifier: "%.0f") об/мин"))
                    Slider(value: $upperRPM, in: minimum...max(minimum + 1, fan.maximum), step: 50)
                    Text(L("Между двумя температурами обороты повышаются плавно; при потере датчика включается автоматика."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(L("Применить")) {
                    model.apply(id: fan.id, configuration: FanConfiguration(mode: mode,
                        minimumRPM: min(fan.maximum, max(minimum, lowerRPM)),
                        maximumRPM: min(fan.maximum, max(lowerRPM, upperRPM)),
                        startTemperature: start, fullTemperature: full, sensor: sensor))
                }.buttonStyle(.borderedProminent).disabled(model.authorizing)
                Text(L("При включении пользовательского режима macOS запросит пароль администратора. Помощник работает только до окончания сессии; постоянная служба не устанавливается."))
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text(L10n.text(fan.issue ?? L("Доступно только чтение оборотов."))).foregroundStyle(.secondary) }
        }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .onAppear { lowerRPM = minimum; upperRPM = fan.maximum }
    }
}
