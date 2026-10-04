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

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases.filter { $0 != .fans || !fanModel.fans.isEmpty }, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationTitle("MacPulse")
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 230)
        } detail: {
            Group {
                switch selection ?? .monitor {
                case .monitor: DashboardView(model: model)
                case .cleaner: CleanerView(model: model.cleaner)
                case .settings: SettingsView(model: model)
                case .fans: FansView(model: fanModel)
                }
            }
            .navigationTitle((selection ?? .monitor).rawValue)
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}
