import AppKit
import SwiftUI
import MonitorCore

@main
struct iMacMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: MonitorModel

    init() {
        let model = MonitorModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear { configure() }
        } label: {
            MenuBarLabel(model: model)
                .onAppear { configure() }
        }
        .menuBarExtraStyle(.window)

        Window("MacPulse", id: "dashboard") {
            MainWindowView(model: model)
                .onAppear { configure() }
        }
        .defaultSize(width: 1040, height: 780)
    }

    private func configure() {
        delegate.model = model
        model.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: MonitorModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
