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
    @Published private(set) var metadata: [String: ApplicationMetadata] = [:]
    @Published private(set) var loadingMetadata = false
    private let metadataService = ApplicationMetadataService()
    private var metadataTask: Task<Void, Never>?
    private var metadataGeneration = UUID()
    private let service = UninstallerService()
    private var task: Task<Void, Never>?
    var selectedBytes: UInt64 { preview?.items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes } ?? 0 }

    func refresh() {
        guard !busy else { return }
        busy = true; message = nil
        task = Task {
            defer { busy = false }
            do { applications = try await service.applications(); loadMetadata() }
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
                applications = try await service.applications(); loadMetadata()
            } catch {
                self.preview = nil; selected = []
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel() }
    private func loadMetadata() {
        metadataTask?.cancel()
        let apps = applications
        let generation = UUID(); metadataGeneration = generation
        metadata = metadata.filter { key, _ in apps.contains { $0.id == key } }
        metadataTask = Task {
            loadingMetadata = true
            defer { if metadataGeneration == generation { loadingMetadata = false } }
            for app in apps {
                do { let value = try await metadataService.read(app.url); try Task.checkCancellation(); metadata[app.id] = value }
                catch { if Task.isCancelled { return } }
            }
        }
    }
    func stop() async {
        task?.cancel(); metadataTask?.cancel()
        await task?.value; await metadataTask?.value
    }
}
