import MonitorCore
import SwiftUI

private enum MainSection: String, CaseIterable, Identifiable {
    case monitor = "Монитор", cleaner = "Очистка", fans = "Вентиляторы", settings = "Настройки"
    var id: Self { self }
    var icon: String {
        switch self {
        case .monitor: "chart.xyaxis.line"
        case .cleaner: "sparkles"
        case .settings: "gearshape"
        case .fans: "fan"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var fanModel: FanModel
    @State private var selection: MainSection? = .monitor

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        NavigationSplitView {
            List(MainSection.allCases.filter { $0 != .fans || !fanModel.fans.isEmpty }, selection: $selection) { section in
                Label(L10n.text(section.rawValue), systemImage: section.icon).tag(section)
            }
            .navigationTitle("MacPulse")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } detail: {
            Group {
                switch selection ?? .monitor {
                case .monitor: DashboardView(model: model)
                case .cleaner: CleanerView(model: model.cleaner)
                case .settings: SettingsView(model: model)
                case .fans: FansView(model: fanModel)
                }
            }
            .navigationTitle(L10n.text((selection ?? .monitor).rawValue))
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}
