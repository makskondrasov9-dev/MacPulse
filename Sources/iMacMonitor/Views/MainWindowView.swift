import AppKit
import MonitorCore
import SwiftUI

private enum MainSection: String, CaseIterable, Identifiable {
    case monitor = "Монитор", cleaner = "Очистка", fans = "Вентиляторы", settings = "Настройки", uninstaller = "Деинсталлятор"
    var id: Self { self }
    var icon: String {
        switch self {
        case .monitor: "chart.xyaxis.line"
        case .cleaner: "sparkles"
        case .settings: "gearshape"
        case .fans: "fan"
        case .uninstaller: "trash"
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
        GeometryReader { geometry in
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
                    case .uninstaller: UninstallerView(model: model.uninstaller)
                    }
                }
                .navigationTitle(L10n.text((selection ?? .monitor).rawValue))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 680, minHeight: 500)
        .background(WindowContentBoundary())
    }
}

/// Sonoma can retain an oversized native split-view frame after window resizing.
/// Size the outer split to its container and keep content below the native toolbar.
private struct WindowContentBoundary: NSViewRepresentable {
    final class BoundaryView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.fitSplitView() }
        }
        private weak var fittedSplit: NSSplitView?
        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.fitSplitView() }
        }
        private func fitSplitView() {
            func firstSplit(in view: NSView) -> NSSplitView? {
                if let split = view as? NSSplitView { return split }
                return view.subviews.lazy.compactMap { firstSplit(in: $0) }.first
            }
            guard let window, let content = window.contentView,
                  let split = firstSplit(in: content),
                  let guide = window.contentLayoutGuide as? NSLayoutGuide else { return }
            guard fittedSplit !== split else { return }
            fittedSplit = split
            split.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                split.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                split.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                split.topAnchor.constraint(equalTo: guide.topAnchor),
                split.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
            ])
        }
    }
    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ nsView: BoundaryView, context: Context) { nsView.needsLayout = true }
}
