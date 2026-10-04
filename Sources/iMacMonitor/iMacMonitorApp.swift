import AppKit
import SwiftUI
import MonitorCore

@main
struct iMacMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("appearance") private var appearance = "system"
    @StateObject private var model: MonitorModel
    private var colorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    init() {
        // Packaging smoke test: validates the shipped resources without starting any services.
        if CommandLine.arguments.contains("--verify-localizations") {
            let source = Set(L10n.catalogs["en"]?.keys.map { $0 } ?? [])
            let valid = !source.isEmpty && AppLanguage.allCases.filter { $0 != .system }.allSatisfy {
                Set(L10n.catalogs[$0.rawValue]?.keys.map { $0 } ?? []) == source
            }
            print(valid ? "MacPulse: 12 language catalogs verified" : "MacPulse: missing language resources")
            exit(valid ? 0 : 1)
        }
        let model = MonitorModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .environment(\.locale, Locale(identifier: AppLanguage.resolve(language).rawValue))
                .environment(\.layoutDirection, AppLanguage.resolve(language) == .ar ? .rightToLeft : .leftToRight)
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
                .environment(\.locale, Locale(identifier: AppLanguage.resolve(language).rawValue))
                .environment(\.layoutDirection, AppLanguage.resolve(language) == .ar ? .rightToLeft : .leftToRight)
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
