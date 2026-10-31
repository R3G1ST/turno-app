import SwiftUI
import AppKit

// MARK: - Главный экран: месячный календарь

struct ScheduleView: View {
    @EnvironmentObject var store: Store
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var editedDay: Date?
    @State private var showTemplates = false
    @State private var copiedFlash = false

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // понедельник
        return c
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    /// Все дни месяца + пустые ячейки для выравнивания по неделям.
    private var calendarDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let count = Int(interval.duration / 86400)
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
        guard let first = days.first else { return days }
        let leading = cal.component(.weekday, from: first) - cal.firstWeekday
        let pad = (leading + 7) % 7
        return [Date?](repeating: nil, count: pad) + days
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(month: $month, day: day)
                                .contextMenu { dayContextMenu(day) }
                                .popover(isPresented: Binding(
                                    get: { editedDay == day },
                                    set: { if !$0 { editedDay = nil } }
                                )) {
                                    DayEditor(day: day)
                                        .environmentObject(store)
                                }
                                .onTapGesture { editedDay = day }
                        } else {
                            Color.clear.frame(height: 110)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showTemplates) {
            TemplatesSheet(month: month)
                .environmentObject(store)
        }
        .overlay(alignment: .top) {
            if copiedFlash {
                Label("График скопирован как фото", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.snappy, value: copiedFlash)
    }

    // MARK: Шапка дней недели

    private var weekdayHeader: some View {
        let symbols = cal.veryShortWeekdaySymbols
        // veryShortWeekdaySymbols: воскресенье первое — разворачиваем под неделю с понедельника
        let ordered = Array(symbols[1...]) + [symbols[0]]
        return HStack(spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { i, s in
                Text(s)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(i >= 5 ? .red.opacity(0.7) : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 12) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 190)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
            Button("Сегодня") { month = cal.startOfDay(for: Date()) }
                .buttonStyle(.borderless)

            Spacer()

            Button {
                copyScheduleAsImage()
            } label: { Label("Скопировать как фото", systemImage: "photo.on.rectangle") }
                .buttonStyle(.borderless)
                .help("Скопировать график месяца в буфер обмена как изображение")

            Button {
                showTemplates = true
            } label: { Label("Шаблоны заполнения", systemImage: "wand.and.stars") }
                .buttonStyle(.borderless)

            legend
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(ShiftKind.work.color).frame(width: 9, height: 9)
                Text("Смена").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.secondary.opacity(0.35)).frame(width: 9, height: 9)
                Text("Выходной").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: month) { month = d }
    }

    // MARK: Копирование графика как изображения

    private func copyScheduleAsImage() {
        // Рендерим календарь в картинку (always-light, плотные фоны → подходит для мессенджеров).
        let canvas = ScheduleImageCanvas(month: month)
            .environmentObject(store)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0 // чёткое retina-изображение
        guard let nsImage = renderer.nsImage else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // TIFF (для вставки в多数 нативных приложений) + PNG (универсально).
        pasteboard.writeObjects([nsImage])
        if let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }

        withAnimation(.snappy) { copiedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.snappy) { copiedFlash = false }
        }
    }

    @ViewBuilder
    private func dayContextMenu(_ day: Date) -> some View {
        Button("Открыть день") { editedDay = day }
        Divider()
        Menu("Снять всех (сделать выходным)") {
            ForEach(store.data.employees.filter(\.active)) { emp in
                Button(emp.name) {
                    store.setShift(Shift(kind: .off), employee: emp.id, date: day)
                }
            }
        }
    }
}

// MARK: - Ячейка дня календаря

struct DayCell: View {
    @EnvironmentObject var store: Store
    @Binding var month: Date
    let day: Date
    /// true — при рендере в изображение: непрозрачный фон вместо материала.
    var forExport: Bool = false

    private var cal: Calendar { Calendar.current }

    private var isToday: Bool {
        cal.isDateInToday(day)
    }

    private var isOtherMonth: Bool {
        !cal.isDate(day, equalTo: month, toGranularity: .month)
    }

    private var workers: [(emp: Employee, shift: Shift)] {
        store.data.employees.filter(\.active).compactMap { emp in
            let s = store.resolvedShift(employee: emp.id, date: day)
            return s.kind.isWork ? (emp, s) : nil
        }
    }

    private var revenue: DayRevenue { store.revenue(date: day) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            stripes
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 14, weight: isToday ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isToday ? Color.white : (isWeekend && workers.isEmpty ? .red : .primary))
                        .frame(width: 26, height: 22)
                        .background(
                            Circle().fill(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
                        )
                    Spacer()
                    if revenue.total > 0 {
                        Text("\(Int(revenue.total / 1000))k")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.black.opacity(0.30)))
                    }
                }

                if workers.isEmpty {
                    Text("Выходной")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                } else {
                    chips
                    Spacer(minLength: 0)
                }
            }
            .padding(7)
        }
        .frame(height: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cellBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderGradient, lineWidth: isToday ? 2 : 1.2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isOtherMonth ? 0.4 : 1)
        .help(helpText())
    }

    // MARK: Цветные полосы по сотрудникам

    /// Фон ячейки: для картинки — плотный белый, в интерфейсе — полупрозрачный материал.
    private var cellBackground: AnyShapeStyle {
        if isToday { return AnyShapeStyle(Color.accentColor.opacity(0.10)) }
        return AnyShapeStyle(forExport ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial))
    }

    /// Максимум полос на ячейку — больше 6 человек в день не бывает на практике.
    private var stripeWorkers: [(emp: Employee, shift: Shift)] {
        Array(workers.prefix(6))
    }

    @ViewBuilder
    private var stripes: some View {
        if !workers.isEmpty {
            HStack(spacing: 0) {
                ForEach(stripeWorkers, id: \.emp.id) { w in
                    w.emp.color.opacity(isToday ? 0.45 : 0.28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var borderGradient: AnyShapeStyle {
        if workers.isEmpty {
            return AnyShapeStyle(isToday
                                 ? Color.accentColor
                                 : (isWeekend ? Color.red.opacity(0.25) : Color.gray.opacity(0.15)))
        }
        let colors = stripeWorkers.map { $0.emp.color }
        if colors.count == 1 {
            return AnyShapeStyle(colors[0])
        }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Чипы с именами

    private var chips: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(workers.prefix(3), id: \.emp.id) { w in
                HStack(spacing: 3) {
                    Image(systemName: w.emp.role.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(w.emp.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(w.emp.color.gradient))
            }
            if workers.count > 3 {
                Text("+\(workers.count - 3) ещё…")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isWeekend: Bool {
        let wd = cal.component(.weekday, from: day)
        return wd == 1 || wd == 7
    }

    private func helpText() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy, EEEE"
        let names = workers.map { $0.emp.name }.joined(separator: ", ")
        return names.isEmpty ? f.string(from: day) : "\(f.string(from: day)): \(names)"
    }
}

// MARK: - Редактор дня: выбор сотрудников

struct DayEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let day: Date

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f.string(from: day).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.data.employees.filter(\.active)) { emp in
                        EmployeeDayRow(day: day, employee: emp)
                    }
                }
                .padding(10)
            }
            .frame(height: 320)

            Divider()

            let rev = store.revenue(date: day)
            HStack {
                Label("Выручка: \(Int(rev.total)) ₽", systemImage: "banknote")
                    .font(.callout)
                    .foregroundStyle(rev.total > 0 ? .green : .secondary)
                Spacer()
                Text("\(store.workedEmployees(date: day).count) на смене")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(width: 340)
    }
}

struct EmployeeDayRow: View {
    @EnvironmentObject var store: Store
    let day: Date
    let employee: Employee

    private var shift: Shift { store.resolvedShift(employee: employee.id, date: day) }
    private var isWork: Bool { shift.kind.isWork }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(employee.color).frame(width: 8, height: 8)

            Toggle(isOn: Binding(
                get: { isWork },
                set: { on in
                    store.setShift(Shift(kind: on ? .work : .off), employee: employee.id, date: day)
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(employee.name).font(.callout)
                    Text(employee.role.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if isWork {
                Text("полная смена")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isWork ? employee.color.opacity(0.08) : .clear)
        )
    }
}

// MARK: - Шаблоны заполнения месяца

struct TemplatesSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    @State private var selected: UUID?
    @State private var pattern: FillPattern = .twoTwo

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Шаблоны заполнения месяца")
                .font(.headline)

            Picker("Сотрудник", selection: $selected) {
                Text("—").tag(UUID?.none)
                ForEach(store.data.employees.filter(\.active)) { emp in
                    Text("\(emp.name) (\(emp.role.rawValue))").tag(Optional(emp.id))
                }
            }

            Picker("Шаблон", selection: $pattern) {
                ForEach(FillPattern.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }

            Text("Шаблон заполнит весь месяц выбранному сотруднику. Смены — полные, дни отдыха — выходными.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Заполнить") {
                    if let id = selected { apply(id) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func apply(_ emp: UUID) {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return }
        let count = Int(interval.duration / 86400)
        for i in 0..<count {
            guard let d = cal.date(byAdding: .day, value: i, to: interval.start) else { continue }
            let kind: ShiftKind
            switch pattern {
            case .allOff: kind = .off
            case .allFull: kind = .work
            default:
                let cycle = pattern.workDays! + pattern.restDays!
                kind = (i % cycle) < pattern.workDays! ? .work : .off
            }
            store.setShift(Shift(kind: kind), employee: emp, date: d)
        }
        store.saveNow()
    }
}

// MARK: - Холст календаря для экспорта в изображение

/// Воспроизводит сетку месяца с заголовком — используется ImageRenderer для «фото графика».
/// Фоны плотные (белые клетки на светлом фоне) и цветScheme принудительно light.
struct ScheduleImageCanvas: View {
    @EnvironmentObject var store: Store
    let month: Date

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    private var calendarDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let count = Int(interval.duration / 86400)
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
        guard let first = days.first else { return days }
        let leading = cal.component(.weekday, from: first) - cal.firstWeekday
        let pad = (leading + 7) % 7
        return [Date?](repeating: nil, count: pad) + days
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("График смен — \(monthTitle)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text("Turno")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            weekdayHeader

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(month: .constant(month), day: day, forExport: true)
                    } else {
                        Color.clear.frame(height: 110)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 940, alignment: .leading)
        .background(Color(red: 0.95, green: 0.95, blue: 0.96))
    }

    private var weekdayHeader: some View {
        let symbols = cal.veryShortWeekdaySymbols
        let ordered = Array(symbols[1...]) + [symbols[0]]
        return HStack(spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { i, s in
                Text(s)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(i >= 5 ? Color.red.opacity(0.7) : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
