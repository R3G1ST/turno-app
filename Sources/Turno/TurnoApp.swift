import SwiftUI

@main
struct TurnoApp: App {
    @StateObject private var store = Store()
    @StateObject private var updater = Updater()

    var body: some Scene {
        #if os(macOS)
        WindowGroup("Turno — График кальянной") {
            RootView()
                .environmentObject(store)
                .environmentObject(updater)
                .frame(minWidth: 1100, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") {
                    updater.checkManual()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(updater)
        }
        #else
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(updater)
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @State private var tab: Tab = .schedule
    @State private var showSettings = false

    enum Tab: String, CaseIterable, Identifiable {
        case schedule = "График"
        case day = "День"
        case payroll = "Зарплата"
        case employees = "Сотрудники"
        case settings = "Настройки"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .schedule: return "calendar"
            case .day: return "banknote"
            case .payroll: return "dollarsign.circle"
            case .employees: return "person.2"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: macOS — боковая панель

    private var macBody: some View {
        VStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .background(.background)
        .onAppear {
            if store.data.checkUpdatesOnLaunch {
                updater.checkSilent()
            }
        }
        .sheet(item: $updater.updateInfo) { info in
            UpdateSheet(info: info)
                .environmentObject(updater)
        }
        // Единый алерт результата импорта (работает и на маке, если импортировали файл).
        .alert(store.importMessageHasError ? "Импорт не удался" : "Импорт данных",
               isPresented: Binding(get: { store.importMessage != nil },
                                    set: { if !$0 { store.importMessage = nil } })) {
            Button("OK") { store.importMessage = nil }
        } message: {
            Text(store.importMessage ?? "")
        }
    }

    private var sidebar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases.filter { $0 != .settings }) { t in
                SidebarButton(icon: t.icon, title: t.rawValue, selected: tab == t) {
                    tab = t
                }
            }

            SidebarButton(icon: "gearshape", title: "Настройки", selected: showSettings) {
                showSettings = true
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(updater)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .schedule: ScheduleView()
        case .day: DayView()
        case .payroll: PayrollView()
        case .employees: EmployeesView()
        case .settings: EmptyView()
        }
    }

    // MARK: iOS — нижние вкладки

    private var iosBody: some View {
        TabView(selection: $tab) {
            ScheduleView()
                .environmentObject(store)
                .environmentObject(updater)
                .tabItem { Label("График", systemImage: Tab.schedule.icon) }
                .tag(Tab.schedule)
            DayView()
                .environmentObject(store)
                .tabItem { Label("Выручка", systemImage: Tab.day.icon) }
                .tag(Tab.day)
            PayrollView()
                .environmentObject(store)
                .tabItem { Label("Зарплата", systemImage: Tab.payroll.icon) }
                .tag(Tab.payroll)
            EmployeesView()
                .environmentObject(store)
                .tabItem { Label("Люди", systemImage: Tab.employees.icon) }
                .tag(Tab.employees)
            SettingsView()
                .environmentObject(store)
                .environmentObject(updater)
                .tabItem { Label("Настройки", systemImage: Tab.settings.icon) }
                .tag(Tab.settings)
        }
        // Импорт данных файлом: «Поделиться → Turno» или «Открыть в Turno» из Файлов.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            store.importFromFile(url: url)
        }
        // Единый алерт результата импорта (из пикера или из шаринга).
        .alert(store.importMessageHasError ? "Импорт не удался" : "Импорт данных",
               isPresented: Binding(get: { store.importMessage != nil },
                                    set: { if !$0 { store.importMessage = nil } })) {
            Button("OK") { store.importMessage = nil }
        } message: {
            Text(store.importMessage ?? "")
        }
    }
}

// MARK: - Кнопка панели с мгновенной отдачей

/// Кастомный стиль: подсветка и лёгкое сжатие появляются сразу при нажатии,
/// клик срабатывает на всей площади кнопки.
struct SidebarPressStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        selected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                        : AnyShapeStyle(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct SidebarButton: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(SidebarPressStyle(selected: selected))
    }
}
