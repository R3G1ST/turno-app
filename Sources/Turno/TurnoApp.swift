import SwiftUI

@main
struct TurnoApp: App {
    @StateObject private var store = Store()
    @StateObject private var updater = Updater()

    var body: some Scene {
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
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @State private var tab: Tab = .schedule

    enum Tab: String, CaseIterable, Identifiable {
        case schedule = "График"
        case day = "День"
        case payroll = "Зарплата"
        case employees = "Сотрудники"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .schedule: return "calendar"
            case .day: return "banknote"
            case .payroll: return "dollarsign.circle"
            case .employees: return "person.2"
            }
        }
    }

    var body: some View {
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
    }

    private var sidebar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(t.rawValue)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tab == t ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .schedule: ScheduleView()
        case .day: DayView()
        case .payroll: PayrollView()
        case .employees: EmployeesView()
        }
    }
}
