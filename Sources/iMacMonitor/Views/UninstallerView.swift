import AppKit
import MonitorCore
import SwiftUI

struct UninstallerView: View {
    @ObservedObject var model: UninstallerModel
    @State private var query = ""
    @State private var confirming = false
    @State private var targeted = false
    @Environment(\.locale) private var locale
    private var visible: [InstalledApplication] {
        model.applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Перетащите .app сюда или выберите приложение. Удаление выполняется только после подтверждения."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button(L("Обновить список")) { model.refresh() }
                    .fixedSize().disabled(model.busy)
            }
            if model.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L("Проверка файлов…"))
                    Spacer()
                    Button(L("Отмена")) { model.cancel() }
                }
            }
            if let message = model.message { Text(L10n.text(message)).foregroundStyle(.secondary).textSelection(.enabled) }
            GeometryReader { geometry in
                if geometry.size.width < 720 {
                    VStack(spacing: 12) {
                        applicationList.frame(height: 170)
                        Divider()
                        detailPane
                    }
                } else {
                    HStack(spacing: 0) {
                        applicationList
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                            .frame(width: min(380, max(280, geometry.size.width * 0.28)))
                        Divider()
                        detailPane.frame(minWidth: 360, maxWidth: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .padding(20)
        .background(targeted ? Color.accentColor.opacity(0.08) : .clear)
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.busy, urls.count == 1, let url = urls.first else { return false }
            model.inspect(url); return true
        } isTargeted: { targeted = $0 }
        .task { if model.applications.isEmpty { model.refresh() } }
        .alert(L("Удалить выбранные файлы навсегда?"), isPresented: $confirming) {
            Button(L("Отмена"), role: .cancel) {}
            Button(L("Удалить"), role: .destructive) { model.remove() }
        } message: {
            Text(L("\(model.preview?.application.name ?? "") · \(ByteSizeFormat.string(model.selectedBytes)). Отмена после удаления невозможна."))
        }
    }

    private var applicationList: some View {
        VStack {
            TextField(L("Поиск приложений"), text: $query).textFieldStyle(.roundedBorder)
            List(visible) { app in
                Button { model.inspect(app.url) } label: {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading) {
                            Text(app.name).lineLimit(2)
                            Text("\(app.version) · \(app.architecture)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(model.busy)
            }
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let scan = model.preview {
                    Text(scan.application.name).font(.title2.bold())
                    Text(scan.application.bundleID).font(.caption).textSelection(.enabled)
                    Text(L("Найдено: \(ByteSizeFormat.string(scan.bytes))"))
                    Text(L("Данные приложения могут содержать проекты и настройки. Проверьте выбранные пути. Совпадения только по названию не выбраны автоматически."))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(scan.items) { item in
                        Toggle(isOn: Binding(get: { model.selected.contains(item.id) }, set: {
                            if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.isApplication ? L("Приложение") : item.url.lastPathComponent).font(.headline)
                                Text(item.url.path).font(.caption).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(ByteSizeFormat.string(item.bytes)).font(.callout.monospacedDigit())
                                if item.nameMatch { Text(L("Совпадение по названию — проверьте владельца")).font(.caption).foregroundStyle(.orange) }
                            }
                        }.toggleStyle(.checkbox).disabled(model.busy)
                        Divider()
                    }
                    if !scan.issues.isEmpty {
                        DisclosureGroup(L("Недоступные и пропущенные файлы")) {
                            ForEach(Array(scan.issues.enumerated()), id: \.offset) { _, issue in
                                Text(L10n.text(issue)).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    Text(L("Выбрано: \(ByteSizeFormat.string(model.selectedBytes))")).font(.headline)
                    Button(scan.items.contains { $0.isApplication && model.selected.contains($0.id) } ? L("Удалить приложение полностью") : L("Удалить"), role: .destructive) { confirming = true }
                        .disabled(model.busy || model.selected.isEmpty)
                    Text(L("Удаляются только выбранные объекты. Общие папки и неизвестные остатки не затрагиваются."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if let result = model.result {
                    Label(L("Удалено объектов: \(result.removedItems) · \(ByteSizeFormat.string(result.removedBytes))"), systemImage: result.removedItems > 0 ? "checkmark.circle" : "info.circle")
                        .font(.title2).foregroundStyle(result.removedItems > 0 ? Color.accentColor : Color.secondary)
                    ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in Text(L10n.text(issue)).font(.caption).textSelection(.enabled) }
                } else {
                    ContentUnavailableView(L("Выберите приложение"), systemImage: "app.dashed")
                }
            }
            .frame(maxWidth: 850, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
