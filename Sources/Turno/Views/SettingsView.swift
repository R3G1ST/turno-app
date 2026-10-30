import SwiftUI
import AppKit

// MARK: - Настройки: пороги надбавок, бэкап, обновления

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @State private var backupMsg: String?

    var body: some View {
        TabView {
            thresholdsTab
                .tabItem { Label("Надбавки", systemImage: "percent") }
            dataTab
                .tabItem { Label("Данные", systemImage: "externaldrive") }
            updatesTab
                .tabItem { Label("Обновления", systemImage: "arrow.down.circle") }
        }
        .frame(width: 520, height: 380)
    }

    // MARK: Пороги

    private var thresholdsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Надбавки за выручку заведения")
                .font(.headline)
            Text("Если дневная выручка достигла порога, каждый работник смены получает надбавку.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach($store.data.thresholds) { $t in
                HStack {
                    Text("Выручка ≥")
                        .font(.callout)
                    TextField("", value: $t.revenueFrom, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Text("₽ → +")
                        .font(.callout)
                    TextField("", value: $t.amount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("₽").font(.callout)
                    Toggle("", isOn: $t.enabled).toggleStyle(.switch).labelsHidden()
                    Button {
                        store.data.thresholds.removeAll { $0.id == t.id }
                        store.saveNow()
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                .padding(10)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }

            Button {
                store.data.thresholds.append(BonusThreshold(revenueFrom: 0, amount: 300))
                store.saveNow()
            } label: { Label("Добавить порог", systemImage: "plus") }

            Spacer()
        }
        .padding(18)
    }

    // MARK: Данные

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Хранение данных")
                .font(.headline)
            Text("Файл: \(Store.dataFile.path)")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Создать резервную копию") {
                    do {
                        try store.backup()
                        backupMsg = "Копия сохранена в Backups"
                    } catch {
                        backupMsg = "Ошибка: \(error.localizedDescription)"
                    }
                }
                if let msg = backupMsg {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            Button("Открыть папку данных") {
                NSWorkspace.shared.open(Store.supportDir)
            }

            Spacer()
            Text("Последние 10 копий хранятся автоматически в папке Backups.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
    }

    // MARK: Обновления

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Обновления")
                .font(.headline)
            Text("Turno \(Updater.currentVersion) · GitHub: R3G1ST/turno-app")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Проверять обновления при запуске", isOn: $store.data.checkUpdatesOnLaunch)
                .onChange(of: store.data.checkUpdatesOnLaunch) { _, _ in store.saveSoon() }

            Button("Проверить сейчас") { updater.checkManual() }

            if let info = updater.updateInfo {
                Text("Доступна версия \(info.version)")
                    .foregroundStyle(.green)
            } else if updater.lastCheckDone {
                Text("У вас последняя версия ✓")
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text("Обновления устанавливаются автоматически: скачивается образ .app с GitHub Releases и заменяет приложение. Данные не затрагиваются.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
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
        .frame(width: 420)
    }
}
