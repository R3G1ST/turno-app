import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Настройки: пороги надбавок, бэкап, обновления

/// Направление ручной синхронизации с GitHub (с подтверждением).
private enum SyncDirection {
    case download
    case upload
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var sync: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var backupMsg: String?
    @State private var tab: Tab = .thresholds
    @State private var showImport = false
    @State private var transferMsg: String?
    @State private var transferMsgHasError = false
    @State private var pendingDirection: SyncDirection?

    enum Tab: String, CaseIterable, Identifiable {
        case thresholds = "Надбавки"
        case data = "Данные"
        case sync = "Связь"
        case updates = "Обновления"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Прокрутка нужна на обеих платформах: порогов может быть много,
            // и без неё SwiftUI сжимает шапку с вкладками до нулевой высоты.
            ScrollView {
                tabContent
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
        }
        #if os(macOS)
        .frame(width: 700, height: 620)
        #endif
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pendingDirection != nil },
            set: { if !$0 { pendingDirection = nil } }
        ), titleVisibility: .visible) {
            Button(confirmationButton) {
                let direction = pendingDirection
                pendingDirection = nil
                switch direction {
                case .download: sync.downloadNow()
                case .upload: sync.uploadNow()
                case nil: break
                }
            }
            Button("Отмена", role: .cancel) { pendingDirection = nil }
        } message: {
            Text(confirmationMessage)
        }
        .fileImporter(isPresented: $showImport,
                      // .item — принимаем файл любого типа: мессенджеры/AirDrop могут
                      // снять расширение или переименовать, а фильтр по .json тогда
                      // прячет файл из списка и импорт невозможен.
                      allowedContentTypes: [.item, .json, .data, .text],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.importFromFile(url: url)
                }
            case .failure(let err):
                // Отмена (просто закрыли окно) — не показываем ошибку.
                if (err as NSError).code != NSUserCancelledError {
                    transferMsg = "Не удалось открыть выбор файла: \(err.localizedDescription)"
                    transferMsgHasError = true
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .thresholds: thresholdsTab
        case .data: dataTab
        case .sync: syncTab
        case .updates: updatesTab
        }
    }

    private var confirmationTitle: String {
        switch pendingDirection {
        case .download: return "Заменить данные на этом устройстве?"
        case .upload: return "Сделать эти данные главными?"
        case nil: return ""
        }
    }

    private var confirmationButton: String {
        switch pendingDirection {
        case .download: return "Скачать с GitHub"
        case .upload: return "Загрузить на GitHub"
        case nil: return ""
        }
    }

    private var confirmationMessage: String {
        switch pendingDirection {
        case .download:
            return "Текущие данные будут заменены копией из GitHub. Перед заменой автоматически создаётся резервная копия в Backups."
        case .upload:
            return "Данные с этого устройства перезапишут файл в GitHub. Записи, которых здесь нет, будут удалены и на другом устройстве. Перед отправкой создаётся резервная копия."
        case nil:
            return ""
        }
    }

    /// Экспорт данных в JSON: на маке — окно сохранения, на телефоне — шторка «Поделиться».
    private func exportJSON() {
        do {
            let data = try store.exportJSON()
            let name = "Turno_данные.json"
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [.json]
            panel.begin { resp in
                if resp == .OK, let url = panel.url {
                    try? data.write(to: url)
                    transferMsg = "Файл сохранён — отправьте его на другое устройство"
                    transferMsgHasError = false
                }
            }
            #else
            ShareFile.present(data: data, fileName: name)
            transferMsg = "Отправьте файл на другое устройство (AirDrop и т.п.)"
            transferMsgHasError = false
            #endif
        } catch {
            transferMsg = "Ошибка экспорта: \(error.localizedDescription)"
            transferMsgHasError = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Настройки")
                    .font(.title3.weight(.semibold))
                Text("Надбавки, данные и обновления")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            #if os(macOS)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Закрыть (Esc)")
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(windowChrome)
    }

    /// На macOS прячем системный разделитель шапки листа; на iOS ничего не нужно.
    @ViewBuilder
    private var windowChrome: some View {
        #if os(macOS)
        WindowConfigurator()
        #else
        Color.clear
        #endif
    }

    // MARK: Пороги

    private var thresholdsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Надбавки за выручку")
                    .font(.headline)
                Text("Когда дневная выручка достигает порога, каждый работник смены получает надбавку.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach($store.data.thresholds) { $t in
                thresholdCard($t)
            }

            if store.data.thresholds.isEmpty {
                Label("Порогов пока нет", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                Haptics.tap()
                withAnimation(.snappy) {
                    store.data.thresholds.append(BonusThreshold(revenueFrom: 0, amount: 300))
                }
                store.saveNow()
            } label: {
                Label("Добавить порог", systemImage: "plus.circle.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())

            #if os(macOS)
            Spacer(minLength: 0)
            #endif
        }
    }

    private func thresholdCard(_ t: Binding<BonusThreshold>) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(t.wrappedValue.enabled ? Color.accentColor : Color.secondary)
                Text("Порог выручки")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: t.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Порог включён")
                Button {
                    Haptics.warning()
                    withAnimation(.snappy) {
                        store.data.thresholds.removeAll { $0.id == t.wrappedValue.id }
                    }
                    store.saveNow()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Удалить порог")
            }

            HStack(alignment: .bottom, spacing: 8) {
                thresholdField("Выручка от", t.revenueFrom)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
                thresholdField("Надбавка каждому", t.amount)
            }

            Text("При выручке от \(Money.grouped(t.wrappedValue.revenueFrom)) ₽ работник получает +\(Money.grouped(t.wrappedValue.amount)) ₽.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .opacity(t.wrappedValue.enabled ? 1 : 0.62)
        .animation(.snappy, value: t.wrappedValue.enabled)
        .onChange(of: t.wrappedValue.revenueFrom) { _, _ in store.saveSoon() }
        .onChange(of: t.wrappedValue.amount) { _, _ in store.saveSoon() }
        .onChange(of: t.wrappedValue.enabled) { _, _ in store.saveSoon() }
    }

    private func thresholdField(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                TextField("0", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("₽")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Данные

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Хранение данных")
                    .font(.headline)
                Text("Файл turno.json и 10 автоматических копий в папке Backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                dataStat("Сотрудники", "\(store.data.employees.count)", "person.2.fill")
                dataStat("Смены", "\(store.data.shifts.count)", "calendar")
                dataStat("Дни с выручкой", "\(store.data.revenues.count)", "banknote")
                dataStat("Премии и штрафы", "\(store.data.premiums.count + store.data.fines.count)", "star.circle.fill")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(Store.dataFile.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button {
                        do {
                            try store.backup()
                            Haptics.success()
                            backupMsg = "Копия сохранена"
                        } catch {
                            backupMsg = "Ошибка: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Резервная копия", systemImage: "externaldrive.badge.plus")
                    }

                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.open(Store.supportDir)
                    } label: {
                        Label("Открыть папку", systemImage: "folder")
                    }
                    #endif
                }
                .font(.callout)

                if let msg = backupMsg {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Перенос на другое устройство")
                    .font(.headline)
                Text("Экспорт сохраняет все данные в один JSON-файл — отправьте его на другое устройство (AirDrop, мессенджер) и импортируйте там. Импорт заменит текущие данные, они будут заранее сохранены в резервную копию.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    exportJSON()
                } label: {
                    Label("Экспорт", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    showImport = true
                } label: {
                    Label("Импорт", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .font(.callout.weight(.medium))

            #if os(iOS)
            VStack(spacing: 8) {
                Button {
                    store.importFromPasteboard()
                } label: {
                    Label("Импорт из буфера обмена", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.scanInbox()
                    if store.pendingInboxFile == nil {
                        transferMsg = "В папке Turno файлов нет. Положите JSON туда: в Файлах — файл → ⋯ → Переместить → На моём iPhone → Turno."
                        transferMsgHasError = false
                    } else {
                        transferMsg = nil
                    }
                } label: {
                    Label("Импорт из папки приложения", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.callout.weight(.medium))

            Text("Если «Поделиться → Turno» не работает, есть два гарантированных пути:\n1) Файлы → файл → Поделиться → Копировать → здесь «Импорт из буфера обмена».\n2) Файлы → файл → ⋯ → Переместить → На моём iPhone → Turno → здесь «Импорт из папки приложения» (или просто откройте Turno — баннер найдёт файл сам).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let last = store.lastOpenedFile {
                Text("Последний открытый файл: \(last)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            #endif

            if let transferMsg {
                Label(transferMsg, systemImage: transferMsgHasError ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(transferMsgHasError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            #if os(macOS)
            Spacer(minLength: 0)
            #endif
        }
        .animation(.snappy, value: transferMsg)
    }

    private func dataStat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Связь

    private var syncTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Синхронизация через GitHub")
                        .font(.headline)
                    Text("Изменения отправляются автоматически через 0,4 секунды и появляются на втором устройстве примерно за секунду. Данные сливаются по записям — свежая правка побеждает, удаления не воскресают.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if sync.isSyncing {
                    ProgressView().controlSize(.small)
                }
            }

            githubCard
            syncStatus

            Label("Локальная синхронизация по Wi-Fi временно отключена — она вернётся позже. Сейчас все устройства обмениваются данными через GitHub.", systemImage: "wifi.slash")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Токен хранится только на устройстве и не попадает в файл синхронизации. На Mac и iPhone нужны одинаковые репозиторий и токен.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            #if os(macOS)
            Spacer(minLength: 0)
            #endif
        }
    }

    private var githubCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.callout.weight(.semibold))
                Spacer()
                Toggle("Авто", isOn: $sync.autoGitHub)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Синхронизировать при запуске, возврате в приложение и после изменений")
            }

            VStack(spacing: 6) {
                TextField("Репозиторий: R3G1ST/turno-sync", text: $sync.githubRepo)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                SecureField("Fine-grained token (Contents: Read and write)", text: $sync.githubToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    sync.syncNow()
                } label: {
                    Label("Слить", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Haptics.select()
                    pendingDirection = .download
                } label: {
                    Label("Скачать", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Haptics.select()
                    pendingDirection = .upload
                } label: {
                    Label("Загрузить", systemImage: "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.callout.weight(.medium))
            .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let error = sync.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(sync.statusMessage, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Последняя успешная синхронизация: \(sync.lastSyncText)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Обновления

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Обновления")
                    .font(.headline)
                Text("Turno \(Updater.currentVersion) · R3G1ST/turno-app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Проверять обновления при запуске", isOn: $store.data.checkUpdatesOnLaunch)
                    .font(.callout)
                    .onChange(of: store.data.checkUpdatesOnLaunch) { _, _ in
                        Haptics.select()
                        store.saveSoon()
                    }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        updater.checkManual()
                    } label: {
                        Label("Проверить сейчас", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)

                    if updater.updateInfo != nil {
                        Label("Есть обновление", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else if updater.lastCheckDone {
                        Label("Актуальная версия", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let info = updater.updateInfo {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.green)
                    Text("Доступна версия \(info.version)")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Обновить") {
                        updater.install(info)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(14)
                .background(Color.green.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Обновления устанавливаются автоматически: скачивается образ .app с GitHub Releases и заменяет приложение. Данные не затрагиваются.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            #if os(macOS)
            Spacer(minLength: 0)
            #endif
        }
    }
}

// MARK: - Окно обновления

struct UpdateSheet: View {
    @EnvironmentObject var updater: Updater
    let info: UpdateInfo

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Доступно обновление Turno \(info.version)")
                .font(.title3.weight(.semibold))
            if !info.notes.isEmpty {
                ScrollView {
                    Text(info.notes)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            }
            if updater.isInstalling {
                ProgressView("Установка… \(Int(updater.progress * 100))%")
            } else {
                HStack {
                    Button("Позже") { updater.updateInfo = nil }
                    Button("Обновить") { updater.install(info) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            if let err = updater.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(28)
#if os(macOS)
        .frame(width: 420)
#else
        .frame(maxWidth: .infinity)
#endif
    }
}

// MARK: - Уборка системной полоски-разделителя у листа настроек

#if os(macOS)
/// macOS рисует горизонтальный разделитель под шапкой листа (titlebar separator).
/// Находим окно листа и отключаем его, а шапку делаем прозрачной.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            configure(v.window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        if let tb = window.standardWindowButton(.closeButton)?.superview {
            tb.isHidden = true   // у листа своя шапка — системную прячем целиком
        }
    }
}
#endif
