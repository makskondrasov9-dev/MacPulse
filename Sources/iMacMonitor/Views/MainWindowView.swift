import SwiftUI

private enum MainSection: String, CaseIterable, Identifiable {
    case monitor = "Монитор", cleaner = "Очистка", settings = "Настройки"
    var id: Self { self }
    var icon: String {
        switch self {
        case .monitor: "chart.xyaxis.line"
        case .cleaner: "sparkles"
        case .settings: "gearshape"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var model: MonitorModel
    @State private var selection: MainSection? = .monitor

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $selection) { section in
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
                }
            }
            .navigationTitle((selection ?? .monitor).rawValue)
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}
