import AppKit
import SwiftUI
import MonitorCore

@main
struct iMacMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appearance") private var appearance = "system"
    @StateObject private var model: MonitorModel
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    init() {
        let model = MonitorModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .preferredColorScheme(colorScheme)
                .onChange(of: appearance, initial: true) { _, value in
                    NSApp.appearance = value == "dark" ? NSAppearance(named: .darkAqua) :
                        (value == "light" ? NSAppearance(named: .aqua) : nil)
                }
                .onAppear { configure() }
        } label: {
            MenuBarLabel(model: model)
                .onAppear { configure() }
        }
        .menuBarExtraStyle(.window)

        Window("MacPulse", id: "dashboard") {
            MainWindowView(model: model, fanModel: model.fans)
                .preferredColorScheme(colorScheme)
                .onChange(of: appearance, initial: true) { _, value in
                    NSApp.appearance = value == "dark" ? NSAppearance(named: .darkAqua) :
                        (value == "light" ? NSAppearance(named: .aqua) : nil)
                }
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
