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
                // Приём файла («Поделиться → Turno») — на самом корне дерева вьюх,
                // чтобы событие открытия не терялось где-то внутри вкладок.
                .onOpenURL { url in
                    store.handleOpenedURL(url)
                }
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .schedule
    @State private var showSettings = false

    enum Tab: String, CaseIterable, Identifiable {
        case schedule = "График"
        case day = "Выручка"
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
        rootContent
            .overlay(alignment: .top) { importBanner }
            // Страховка на случай, если событие открытия файла потерялось:
            // проверяем папку Inbox при появлении экрана и при каждом возврате
            // приложения из фона (туда iOS кладёт открытый файл).
            .onAppear { store.scanInbox() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.scanInbox() }
            }
            // Файл может оказаться в папке чуть позже появления экрана
            // (система докладывает его во время открытия) — перепроверяем.
            .task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                store.scanInbox()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                store.scanInbox()
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    /// Гарантированно видимый результат импорта: баннер поверх всего экрана.
    /// (Системный алерт при открытии файла из шаринга может не появиться —
    /// окно ещё не готово, и сообщение «терялось».)
    private var importBanner: some View {
        Group {
            if let msg = store.importMessage {
                bannerCard(
                    title: store.importMessageHasError ? "Импорт не удался" : "Импорт данных",
                    icon: store.importMessageHasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    text: msg,
                    hint: "Нажмите, чтобы закрыть",
                    error: store.importMessageHasError
                ) { store.importMessage = nil }
            } else if let file = store.pendingInboxFile {
                // Файл дошёл до папки приложения, но событие открытия не сработало.
                bannerCard(
                    title: "Найден файл данных",
                    icon: "doc.badge.gearshape",
                    text: "Файл «\(file.lastPathComponent)» поступил в Turno.\nНажмите, чтобы импортировать данные.",
                    hint: "Нажмите, чтобы импортировать",
                    error: false
                ) { store.acceptPendingInboxFile() }
            }
        }
        .animation(.spring(duration: 0.3), value: store.importMessage)
        .animation(.spring(duration: 0.3), value: store.pendingInboxFile)
    }

    private func bannerCard(title: String, icon: String, text: String,
                            hint: String, error: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(error ? Color.red.opacity(0.5) : Color.green.opacity(0.5))
        )
        .shadow(radius: 12, y: 4)
        .padding(.top, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(999)
    }

    /// После успешного импорта сразу показываем календарь с данными.
    private func focusAfterImport() {
        guard !store.importMessageHasError else { return }
        tab = .schedule
        #if os(macOS)
        showSettings = false
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
        .onChange(of: store.importMessage) { _, msg in
            if msg != nil { focusAfterImport() }
        }
    }

    private var sidebar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases.filter { $0 != .settings }) { t in
                SidebarButton(icon: t.icon, title: t.rawValue, selected: tab == t) {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.22)) { tab = t }
                }
            }

            SidebarButton(icon: "gearshape", title: "Настройки", selected: showSettings) {
                Haptics.tap()
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
        Group {
            switch tab {
            case .schedule: ScheduleView()
            case .day: DayView()
            case .payroll: PayrollView()
            case .employees: EmployeesView()
            case .settings: EmptyView()
            }
        }
        .id(tab)
        .transition(.opacity)
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
        // Приём файла из шаринга теперь на корне WindowGroup (см. выше) —
        // здесь остаётся только реакция на результат импорта.
        .onChange(of: store.importMessage) { _, msg in
            if msg != nil { focusAfterImport() }
        }
    }
}

// MARK: - Кнопка панели с мгновенной отдачей

/// Кастомный стиль: подсветка и лёгкое сжатие появляются сразу при нажатии,
/// клик срабатывает на всей площади кнопки.
struct SidebarPressStyle: ButtonStyle {
    var selected: Bool
    var hovering: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        selected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                        : AnyShapeStyle(configuration.isPressed
                                        ? Color.primary.opacity(0.10)
                                        : (hovering ? Color.primary.opacity(0.06) : Color.clear))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72),
                       value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .contentShape(Rectangle())
    }
}

struct SidebarButton: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

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
        .buttonStyle(SidebarPressStyle(selected: selected, hovering: hovering))
        .onHover { hovering = $0 }
    }
}
