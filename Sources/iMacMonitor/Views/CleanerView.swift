import AppKit
import MonitorCore
import SwiftUI

struct CleanerView: View {
    @ObservedObject var model: CleanerModel
    @State private var access: DiskAccessProbe.Status = .unknown
    @State private var confirmDelete = false
    @State private var confirmDeepMode = false
    @State private var linkError = false
    private let probe = DiskAccessProbe()

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Умная очистка")).font(.largeTitle.bold())
                quickCleanCard
                if let error = model.error { Text(L10n.text(error)).foregroundStyle(.red).textSelection(.enabled) }
                if let result = model.result { report(result) }
                Divider()
                header
                if access != .readable {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("Полный доступ к диску не подтверждён"), systemImage: "lock.shield")
                        Text(L("Часть файлов может быть недоступна. Доступ включается вручную в Системных настройках; после изменения разрешения может потребоваться перезапуск MacPulse."))
                            .font(.caption)
                        Button(L("Открыть настройки доступа")) { openPrivacy() }
                        if linkError { Text(L("Откройте Конфиденциальность и безопасность → Полный доступ к диску.")).font(.caption) }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                Toggle(L("Глубокая очистка браузеров"), isOn: Binding(
                    get: { model.deepBrowsers },
                    set: { enabled in
                        if enabled { confirmDeepMode = true }
                        else { model.deepBrowsers = false; model.invalidateScan() }
                    }))
                    .disabled(model.isBusy)
                Text(model.deepBrowsers
                     ? L("В список войдут cookies и данные сайтов. Пароли и закладки исключены. Закройте браузеры перед очисткой.")
                     : L("Безопасный режим: только кэш браузеров в ~/Library/Caches. Профили, авторизации, пароли и вкладки сохраняются."))
                    .font(.caption).foregroundStyle(.secondary)
                if let scan = model.scan {
                    ForEach(scan.issues, id: \.self) { Text(L10n.text($0)).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    HStack {
                        Text(L("Найденные данные: \(scan.bytes.cleanerSize)")).font(.headline)
                        Spacer()
                        Button(L("Выбрать всё")) { model.selected = Set(scan.items.filter { $0.canDelete && $0.fileCount > 0 }.map(\.id)) }
                        Button(L("Снять всё")) { model.selected.removeAll() }
                    }.disabled(model.isBusy)
                    ForEach(CleanerCategory.allCases) { category in
                        let items = scan.items.filter { $0.category == category }
                        if !items.isEmpty { categorySection(category, items: items) }
                    }
                    if scan.items.isEmpty {
                        ContentUnavailableView(L("Данные для очистки не найдены"), systemImage: "checkmark.circle",
                            description: Text(L("Проверьте доступ к диску, если ожидали увидеть больше файлов.")))
                    }
                } else if !model.isBusy && model.result == nil {
                    ContentUnavailableView(L("Начните со сканирования"), systemImage: "magnifyingglass",
                        description: Text(L("Вы увидите пути, размеры и предупреждения до удаления. Ни один файл не удаляется при сканировании.")))
                }
                Text(L("Перед удалением закройте приложения, использующие выбранные данные. Ссылки внутри ~/Library/Caches удаляются без перехода к их содержимому. Ссылки вне кэшей, файлы с несколькими жёсткими ссылками и изменённые после сканирования файлы пропускаются. Папки проектов и неизвестные остатки не удаляются целиком."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(L("Выбрано: \(model.selectedItems.count)"))
                Spacer()
                Button(L("Очистить выбранное (\(model.selectedBytes.cleanerSize))"), role: .destructive) { confirmDelete = true }
                    .disabled(model.isBusy || model.selected.isEmpty)
            }.padding().background(.bar)
        }
        .confirmationDialog(L("Безвозвратно удалить выбранные файлы?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(model.hasSensitiveSelection ? L("Удалить, включая чувствительные данные") : L("Удалить навсегда"), role: .destructive) {
                model.cleanConfirmed()
            }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("\(model.selectedBytes.cleanerSize). Отмена после удаления невозможна. ") +
                 (model.hasSensitiveSelection ? L("Выбраны данные, которые могут включать архивы, Корзину, прокси или cookies. При очистке данных сайтов потребуется повторный вход.\n") : "") +
                 model.selectedItems.filter(\.sensitive).map { L10n.text($0.name) }.joined(separator: "\n"))
        }
        .confirmationDialog(L("Включить глубокую очистку?"), isPresented: $confirmDeepMode, titleVisibility: .visible) {
            Button(L("Включить")) { model.deepBrowsers = true; model.invalidateScan() }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("Будут доступны cookies и локальные данные сайтов. Их удаление завершит авторизации и может удалить офлайн-данные. Этот переключатель ничего не удаляет; выбор файлов и подтверждение потребуются отдельно."))
        }
        .task { access = await probe.check() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { access = await probe.check() }
        }
    }

    private var quickCleanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Больше места — в один клик"), systemImage: "sparkles").font(.title2.bold())
            Text(L("Безопасный кэш браузеров и приложений, логи и отчёты о сбоях. Корзина будет очищена безвозвратно сразу после сканирования."))
                .foregroundStyle(.secondary)
            Text(L("Профили браузеров, архивы и документы сохраняются. Кэши открытых браузеров пропускаются."))
                .font(.caption).foregroundStyle(.secondary)
            Button(action: model.startQuickClean) {
                Label(L("Быстрая очистка"), systemImage: "sparkles").font(.headline).padding(.horizontal, 20).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isBusy)
            if model.isBusy {
                Button(L("Остановить")) { model.cancel() }
                if let progress = model.progress {
                    ProgressView(L10n.text(progress.name), value: Double(progress.completed), total: Double(max(1, progress.total)))
                } else { ProgressView() }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Ручная очистка")).font(.title2.bold())
            HStack {
                Button(L("Сканировать систему")) { model.startScan() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isBusy)

            }

        }
    }

    private func categorySection(_ category: CleanerCategory, items: [CleanerItem]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(isOn: Binding(get: { model.selected.contains(item.id) }, set: { enabled in
                            if enabled { model.selected.insert(item.id) } else { model.selected.remove(item.id) }
                        })) {
                            Text(L("\(L10n.text(item.name)) — \(item.bytes.cleanerSize) · \(item.fileCount) файлов"))
                        }.disabled(!item.canDelete || item.fileCount == 0 || model.isBusy)
                        Text(item.path).font(.caption.monospaced()).textSelection(.enabled)
                        if let note = item.note { Text(L10n.text(note)).font(.caption).foregroundStyle(item.sensitive ? .orange : .secondary) }
                        ForEach(item.issues, id: \.self) { Text(L10n.text($0)).font(.caption).foregroundStyle(.red) }
                    }
                }
            }.padding(.vertical, 10)
        } label: {
            HStack {
                let selectable = Set(items.filter { $0.canDelete && $0.fileCount > 0 }.map(\.id))
                Toggle(isOn: Binding(get: { !selectable.isEmpty && selectable.isSubset(of: model.selected) }, set: { enabled in
                    if enabled { model.selected.formUnion(selectable) } else { model.selected.subtract(selectable) }
                })) { Label(L10n.text(category.rawValue), systemImage: category.icon).font(.headline) }
                    .disabled(selectable.isEmpty || model.isBusy)
                Spacer()
                Text(L("\(items.reduce(UInt64(0)) { $0 + $1.bytes }.cleanerSize) · \(items.reduce(0) { $0 + $1.fileCount }) файлов"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func report(_ result: CleanerResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.cancelled ? L("Очистка остановлена") :
                  (result.removedFiles > 0 || result.issues.isEmpty ? L("Очистка успешно завершена!") : L("Очистка завершена: файлы пропущены")),
                  systemImage: result.cancelled ? "pause.circle" : "checkmark.circle.fill")
                .font(.title2.bold()).foregroundStyle(result.cancelled ? Color.secondary : Color.accentColor)
            if let free = result.availableSpaceIncrease {
                Text(L("Освобождено \(free.cleanerSize)"))
                    .font(.largeTitle.bold()).foregroundStyle(Color.accentColor)
            }
            Text(L("Удалено \(result.removedFiles) файлов · \(result.removedBytes.cleanerSize)"))
            if !result.runningApplications.isEmpty {
                Label {
                    Text(L("Кэш некоторых приложений пропущен, так как они сейчас открыты (\(result.runningApplications.joined(separator: ", "))). Чтобы очистить их полностью, закройте программы и запустите очистку снова."))
                } icon: { Image(systemName: "info.circle").foregroundStyle(Color.accentColor) }
                    .padding().background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if result.skippedFiles > 0 || !result.issues.isEmpty {
                DisclosureGroup(result.skippedFiles > 0 ? L("Подробности пропуска (\(result.skippedFiles) файлов)") : L("Подробности пропуска")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Некоторые объекты недоступны, используются приложениями или изменились после сканирования. Ниже приведены диагностические примеры; число строк может отличаться от числа пропущенных файлов."))
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                            Text(L10n.text(issue)).textSelection(.enabled)
                        }
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            Text(L("Прирост свободного места измеряется отдельно от размера файлов: на него влияют APFS, снимки и другие приложения."))
                .font(.caption).foregroundStyle(.secondary)

        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func openPrivacy() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        linkError = !NSWorkspace.shared.open(url)
    }
}
