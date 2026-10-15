import AppKit
import MonitorCore
import SwiftUI

private enum MainSection: String, CaseIterable, Identifiable {
    case network = "Сеть"
    case monitor = "Монитор", cleaner = "Очистка", fans = "Вентиляторы", settings = "Настройки", uninstaller = "Деинсталлятор", diagnostics = "Diagnostics"
    var id: Self { self }
    var icon: String {
        switch self {
        case .network: "network"
        case .monitor: "chart.xyaxis.line"
        case .cleaner: "sparkles"
        case .settings: "gearshape"
        case .fans: "fan"
        case .uninstaller: "trash"
        case .diagnostics: "testtube.2"
        }
    }
}

struct MainWindowView: View {
    let model: MonitorModel
    let fanModel: FanModel
    @AppStorage("desktopWidgetsEnabled") private var widgets = false
    @State private var selection: MainSection? = .monitor

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        GeometryReader { geometry in
            NavigationSplitView {
                MainSidebar(fanModel: fanModel, selection: $selection)
                .navigationTitle("MacPulse")
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
            } detail: {
                Group {
                    switch selection ?? .monitor {
                    case .network: NetworkProcessesView()
                    case .monitor: DashboardView(model: model)
                    case .cleaner: CleanerView(model: model.cleaner)
                    case .settings: SettingsView(model: model)
                    case .fans: FansView(model: fanModel).onAppear { fanModel.interfaceVisible = true }.onDisappear { fanModel.interfaceVisible = false }
                    case .uninstaller: UninstallerView(model: model.uninstaller)
                    case .diagnostics: DiagnosticsView(model: model.diagnostics)
                    }
                }
                .navigationTitle(L10n.text((selection ?? .monitor).rawValue))
                .toolbar { Toggle(L("Enable desktop widgets"), isOn: Binding(get: { widgets }, set: { WidgetPreferences.setMaster($0) })).toggleStyle(.checkbox) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 680, minHeight: 500)
        .background(WindowContentBoundary())
        .background(MonitorWindowVisibility(model: model))
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
            if window.level != .normal { window.level = .normal }
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

private struct MainSidebar: View {
    @ObservedObject var fanModel: FanModel
    @Binding var selection: MainSection?
    var body: some View {
        List(MainSection.allCases.filter { $0 != .fans || !fanModel.fans.isEmpty }, selection: $selection) { section in
            Label(L10n.text(section.rawValue), systemImage: section.icon).tag(section)
        }
    }
}

private struct MonitorWindowVisibility: NSViewRepresentable {
    let model: MonitorModel
    final class Probe: NSView {
        var model: MonitorModel?
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
            guard let window else { model?.fullInterfaceVisible = false; return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated {
                        if closing { self?.model?.fullInterfaceVisible = false }
                        else { self?.updateVisibility() }
                    }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.updateVisibility() }
        }
        func disconnect() { for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = [] }
        private func updateVisibility() { model?.fullInterfaceVisible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false }
    }
    func makeNSView(context: Context) -> Probe { let probe = Probe(); probe.model = model; return probe }
    func updateNSView(_ view: Probe, context: Context) {}
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.disconnect(); view.model?.fullInterfaceVisible = false }
}
