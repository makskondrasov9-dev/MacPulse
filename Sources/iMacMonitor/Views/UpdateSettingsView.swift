import AppKit
import SwiftUI
import MonitorCore

enum AppAccent: String, CaseIterable {
    case blue = "Blue", purple = "Purple", pink = "Pink", orange = "Orange", green = "Green", graphite = "Graphite"
    var color: Color {
        switch self { case .blue: .blue; case .purple: .purple; case .pink: .pink; case .orange: .orange; case .green: .green; case .graphite: .gray }
    }
}

struct UpdateSettingsView: View {
    @State private var checking = false
    @State private var release: AvailableRelease?
    @State private var status: String?
    @State private var task: Task<Void, Never>?
    private var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ReleaseUpdater.developmentVersion }
    var body: some View {
        Section(L("Updates")) {
            Text("MacPulse \(current)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("Check for updates")) { check() }.disabled(checking)
                if checking { ProgressView().controlSize(.small) }
            }
            if let status { Text(L10n.text(status)).foregroundStyle(.secondary) }
            if let release {
                Text(release.tag).font(.headline)
                Text(release.date, style: .date).foregroundStyle(.secondary)
                Text(L("What's new")).font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(release.notes.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                            Text(markdown(line)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(maxHeight: 240)
                Button(L("Download update")) { NSWorkspace.shared.open(release.download) }.buttonStyle(.borderedProminent)
            }
        }.onDisappear { task?.cancel() }
    }
    private func markdown(_ line: String) -> AttributedString {
        var text = line
        if text.hasPrefix("- ") || text.hasPrefix("* ") { text = "• " + text.dropFirst(2) }
        if text.hasPrefix("#") { text = "**" + text.drop(while: { $0 == "#" || $0 == " " }) + "**" }
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    private func check() {
        checking = true; status = nil; release = nil
        task = Task {
            defer { checking = false }
            do {
                let latest = try await ReleaseUpdater.latest()
                try Task.checkCancellation()
                guard let installed = ReleaseVersion(current) else { status = "Unable to read installed version"; return }
                if latest.version > installed { release = latest }
                else { status = "You have the latest version of MacPulse" }
            } catch {
                if !Task.isCancelled { status = "Could not check for updates. Please try again later." }
            }
        }
    }
}

struct ApplicationMetadataLabel: View {
    let metadata: ApplicationMetadata
    @Environment(\.locale) private var locale
    private var color: Color {
        switch metadata.signature { case .trusted: .green; case .selfSigned: .orange; case .unsigned, .invalid: .red; case .unavailable: .secondary }
    }
    private var relative: String {
        guard let date = metadata.lastUsed else { return L("Never") }
        let formatter = RelativeDateTimeFormatter(); formatter.locale = locale; formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text((metadata.bytes.map { ByteSizeFormat.string($0) } ?? "—") + " · " + relative)
                .help(L(metadata.usesModificationDate ? "Spotlight unavailable: using modification date" : "Last use reported by Spotlight; missing data does not prove an app was never used"))
            Label(L10n.text(metadata.signature.rawValue), systemImage: "checkmark.shield")
                .foregroundStyle(color)
                .help(L("Signature verification does not confirm Apple notarization"))
        }.font(.caption).foregroundStyle(.secondary)
    }
}
