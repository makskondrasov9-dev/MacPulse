import AppKit
import MonitorCore
import SwiftUI

@MainActor
final class UninstallerModel: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var preview: UninstallerPreview?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var result: UninstallerResult?
    @Published var selected: Set<UUID> = []
    private let service = UninstallerService()
    private var task: Task<Void, Never>?
    var selectedBytes: UInt64 { preview?.items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes } ?? 0 }

    func refresh() {
        guard !busy else { return }
        busy = true; message = nil
        task = Task {
            defer { busy = false }
            do { applications = try await service.applications() }
            catch { if !(error is CancellationError) { message = error.localizedDescription } }
        }
    }
    func inspect(_ url: URL) {
        guard !busy else { return }
        busy = true; message = nil; result = nil; preview = nil; selected = []
        task = Task {
            defer { busy = false }
            do {
                let scan = try await service.preview(applicationURL: url)
                try Task.checkCancellation()
                preview = scan
                selected = Set(scan.items.filter { !$0.nameMatch }.map(\.id))
            } catch { if !(error is CancellationError) { message = error.localizedDescription } }
        }
    }
    func remove() {
        guard !busy, let preview else { return }
        let chosen = selected
        busy = true; message = nil
        task = Task {
            defer { busy = false }
            do {
                result = try await service.remove(previewID: preview.id, selected: chosen, confirmed: true)
                self.preview = nil; selected = []
                applications = try await service.applications()
            } catch {
                self.preview = nil; selected = []
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel() }
    func stop() async { task?.cancel(); await task?.value }
}
