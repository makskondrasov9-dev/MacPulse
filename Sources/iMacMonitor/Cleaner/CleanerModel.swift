import Foundation
import MonitorCore
import SwiftUI

@MainActor
final class CleanerModel: ObservableObject {
    @Published private(set) var scan: CleanerScan?
    @Published var selected: Set<UUID> = []
    @Published private(set) var isBusy = false
    @Published private(set) var progress: CleanerProgress?
    @Published private(set) var result: CleanerResult?
    @Published private(set) var error: String?
    @Published var deepBrowsers = false
    private let engine = CleanerActor()
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    var selectedItems: [CleanerItem] { scan?.items.filter { selected.contains($0.id) } ?? [] }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var hasSensitiveSelection: Bool { selectedItems.contains(where: \.sensitive) }

    func invalidateScan() {
        guard !isBusy else { return }
        scan = nil
        selected.removeAll()
        result = nil
    }

    func startQuickClean() {
        guard !isBusy else { return }
        isBusy = true
        scan = nil
        selected.removeAll()
        result = nil
        error = nil
        progress = nil
        let engine = engine
        task = Task(priority: .utility) { [weak self] in
            do {
                self?.result = try await engine.quickClean { [weak self] value in
                    await self?.update(value)
                }
            } catch is CancellationError {
                self?.error = "Сканирование остановлено. Файлы не изменены."
            } catch { self?.error = error.localizedDescription }
            self?.isBusy = false
        }
    }

    func startScan() {
        guard !isBusy else { return }
        isBusy = true
        scan = nil
        selected.removeAll()
        result = nil
        error = nil
        progress = nil
        let engine = engine, deep = deepBrowsers
        task = Task(priority: .utility) { [weak self] in
            do {
                let scan = try await engine.scan(deepBrowsers: deep) { [weak self] value in
                    await self?.update(value)
                }
                self?.scan = scan
            } catch is CancellationError {
                self?.error = "Сканирование остановлено. Файлы не изменены."
            } catch { self?.error = error.localizedDescription }
            self?.isBusy = false
        }
    }

    func cleanConfirmed() {
        guard !isBusy, let scan, !selected.isEmpty else { return }
        let ids = selected, sensitive = hasSensitiveSelection
        isBusy = true
        error = nil
        result = nil
        let engine = engine
        task = Task(priority: .utility) { [weak self] in
            do {
                let result = try await engine.delete(scan: scan.id, selected: ids, confirmed: true,
                                                     sensitiveConfirmed: sensitive) { [weak self] value in
                    await self?.update(value)
                }
                self?.result = result
            } catch { self?.error = error.localizedDescription }
            // No reuse of stale previews after a partial deletion.
            self?.scan = nil
            self?.selected.removeAll()
            self?.isBusy = false
        }
    }

    func cancel() { task?.cancel() }
    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }
    private func update(_ value: CleanerProgress) { progress = value }
}

extension UInt64 {
    var cleanerSize: String { Int64(clamping: self).formatted(.byteCount(style: .file).locale(L10n.locale)) }
}
