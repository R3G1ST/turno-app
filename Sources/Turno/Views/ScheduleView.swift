import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Главный экран: месячный календарь

struct ScheduleView: View {
    @EnvironmentObject var store: Store
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var monthInitialized = false
    @State private var editedDay: Date?
    @State private var showTemplates = false
    @State private var showSummary = false
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    /// Высота ячейки: на телефоне компактнее, чтобы месяц целиком помещался.
    private var cellHeight: CGFloat {
#if os(iOS)
        96
#else
        110
#endif
    }

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
                                .onTapGesture {
                                    Haptics.tap()
                                    editedDay = day
                                }
                                #if os(iOS)
                                .sheet(isPresented: Binding(
                                    get: { editedDay == day },
                                    set: { if !$0 { editedDay = nil } }
                                )) {
                                    DayEditor(day: day)
                                        .environmentObject(store)
                                        .presentationDetents([.medium, .large])
                                        .presentationDragIndicator(.visible)
                                }
                                #else
                                .popover(isPresented: Binding(
                                    get: { editedDay == day },
                                    set: { if !$0 { editedDay = nil } }
                                )) {
                                    DayEditor(day: day)
                                        .environmentObject(store)
                                }
                                #endif
                        } else {
                            Color.clear.frame(height: cellHeight)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        #if os(iOS)
        // Свайп влево/вправо по календарю листает месяцы (вместо стрелок).
        .monthSwipe { shiftMonth($0) }
        #endif
        .sheet(isPresented: $showTemplates) {
            TemplatesSheet(month: month)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSummary) {
            MonthSummarySheet(month: month)
                .environmentObject(store)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .onAppear {
            // При первом открытии показываем месяц с последними данными,
            // а не слепо текущий (иначе после окончания месяца кажется, что данные пропали).
            if !monthInitialized {
                monthInitialized = true
                month = store.lastActiveMonth
            }
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
#if os(iOS)
        compactHeader
#else
        macHeader
#endif
    }

    /// Компактная шапка под узкий экран телефона: месяц + выручка, ниже действия.
    /// Месяц листается свайпом по календарю, поэтому стрелок нет.
    private var compactHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(monthTitle)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.interpolate)

                monthRevenueLabel
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { month = cal.startOfDay(for: Date()) }
                } label: {
                    Text("Сегодня")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0.45 : 1)

                Spacer(minLength: 4)

                headerIcon("chart.bar.xaxis") {
                    showSummary = true
                }
                headerIcon("photo.on.rectangle") {
                    copyScheduleAsImage()
                }
                headerIcon("wand.and.stars") {
                    showTemplates = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// Круглая иконка действия в шапке: зона нажатия 30×30 и пружинка.
    private func headerIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(0.35), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Выручка за показанный месяц. Нажатие открывает сводку месяца.
    private var monthRevenueLabel: some View {
        Button {
            Haptics.tap()
            showSummary = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "banknote").font(.caption2)
                Text("\(Money.grouped(monthRevenue)) ₽")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(monthRevenue > 0 ? Color.green : Color.secondary)
            .background(
                (monthRevenue > 0 ? Color.green : Color.secondary).opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.snappy, value: monthRevenue)
        .accessibilityLabel("Выручка за месяц \(Money.grouped(monthRevenue)) рублей. Открыть сводку месяца")
    }

    private var macHeader: some View {
        HStack(spacing: 12) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Предыдущий месяц (⌘←)")
            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 190)
                .contentTransition(.interpolate)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Следующий месяц (⌘→)")
            Button("Сегодня") { month = cal.startOfDay(for: Date()) }
                .buttonStyle(.borderless)

            Divider().frame(height: 18)

            HStack(spacing: 5) {
                Image(systemName: "banknote").font(.caption)
                Text("Выручка за месяц: \(Money.grouped(monthRevenue)) ₽")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(monthRevenue > 0 ? Color.green : Color.secondary)
            .help("Сумма выручки за все дни показанного месяца")
            .animation(.snappy, value: monthRevenue)

            Spacer()

            Button {
                showSummary = true
            } label: { Label("Сводка месяца", systemImage: "chart.bar.xaxis") }
                .buttonStyle(.borderless)
                .help("Выручка, смены и выплаты за показанный месяц")

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
        guard let d = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy(duration: 0.28)) { month = d }
        Haptics.select()
    }

    /// Суммарная выручка за показанный месяц.
    private var monthRevenue: Double { store.monthRevenue(month) }

    /// Открыт ли текущий календарный месяц (кнопка «Сегодня» тогда неактивна).
    private var isCurrentMonth: Bool {
        cal.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    // MARK: Копирование графика как изображения

    private func copyScheduleAsImage() {
        // Рендерим календарь в картинку (always-light, плотные фоны → подходит для мессенджеров).
        let canvas = ScheduleImageCanvas(month: month)
            .environmentObject(store)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0 // чёткое retina-изображение

        #if os(macOS)
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
        #else
        guard let uiImage = renderer.uiImage else { return }
        UIPasteboard.general.image = uiImage
        #endif

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

    /// Высота ячейки — компактнее на телефоне.
    private var cellHeight: CGFloat {
#if os(iOS)
        96
#else
        110
#endif
    }

    /// Параметры чипов с именами: на телефоне ячейка ~48 pt шириной,
    /// поэтому имя важнее иконки роли — шрифт меньше, но с автоподгонкой,
    /// чтобы имя читалось целиком, а не обрезалось до буквы.
#if os(iOS)
    private let chipFont: CGFloat = 9
    private let chipSpacing: CGFloat = 2
    private let chipHPad: CGFloat = 4
#else
    private let chipFont: CGFloat = 10
    private let chipSpacing: CGFloat = 3
    private let chipHPad: CGFloat = 6
#endif

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
                    #if os(macOS)
                    if revenue.total > 0 {
                        revenueCapsule
                    }
                    #endif
                }

                if workers.isEmpty {
                    Text("Выходной")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    chips
                }
                #if os(iOS)
                // В узкой ячейке телефона капсула выручки не влезает в ряд с числом
                // дня (текст заворачивался в столбик) — показываем её отдельной строкой.
                if revenue.total > 0 {
                    revenueCapsule
                }
                #endif
                Spacer(minLength: 0)
            }
            .padding(7)
        }
        .frame(height: cellHeight, alignment: .topLeading)
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

    /// Капсула выручки дня («15k»).
    private var revenueCapsule: some View {
        Text("\(Int(revenue.total / 1000))k")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(.black.opacity(0.30)))
            .lineLimit(1)
            .fixedSize()
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
        VStack(alignment: .leading, spacing: chipSpacing) {
            ForEach(workers.prefix(3), id: \.emp.id) { w in
                HStack(spacing: 3) {
                    #if os(macOS)
                    Image(systemName: w.emp.role.icon)
                        .font(.system(size: 8, weight: .bold))
                    #endif
                    Text(w.emp.name)
                        .font(.system(size: chipFont, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, chipHPad)
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

// MARK: - Редактор дня: сотрудники + выручка

struct DayEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let day: Date

    @State private var hookahText = ""
    @State private var barText = ""
    @State private var fieldsLoaded = false

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f.string(from: day).capitalized
    }

    private var revTotal: Double {
        (Double(hookahText.replacingOccurrences(of: ",", with: ".")) ?? 0)
        + (Double(barText.replacingOccurrences(of: ",", with: ".")) ?? 0)
    }

    private var bonusEach: Double {
        store.passedThresholds(date: day).reduce(0.0) { $0 + $1.amount }
    }

    private var payout: Double {
        store.workedEmployees(date: day).reduce(0.0) { sum, emp in
            let s = store.resolvedShift(employee: emp.id, date: day)
            return sum + (s.rateOverride ?? emp.defaultShiftRate) + bonusEach
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text("Включите, кто работает в этот день")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") {
                    Haptics.tap()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderless)
                .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.data.employees.filter(\.active)) { emp in
                        EmployeeDayRow(day: day, employee: emp)
                    }

                    if store.data.employees.contains(where: \.active) {
                        HStack(spacing: 8) {
                            quickButton("Все на смене", "person.2.fill") { setAll(true) }
                            quickButton("Выходной всем", "moon.zzz.fill") { setAll(false) }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            #if os(macOS)
            .frame(height: 280)
            #else
            .frame(minHeight: 160)
            #endif

            Divider()
            revenueSection
        }
        #if os(macOS)
        .frame(width: 360)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .onAppear(perform: loadFields)
    }

    private func loadFields() {
        let rev = store.revenue(date: day)
        hookahText = rev.hookah == 0 ? "" : formatted(rev.hookah)
        barText = rev.bar == 0 ? "" : formatted(rev.bar)
        fieldsLoaded = true
    }

    private func formatted(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func setAll(_ working: Bool) {
        Haptics.success()
        withAnimation(.snappy) {
            for emp in store.data.employees where emp.active {
                store.setShift(Shift(kind: working ? .work : .off),
                               employee: emp.id, date: day)
            }
        }
        store.saveNow()
    }

    private func quickButton(_ title: String, _ icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func commit() {
        guard fieldsLoaded else { return }
        let h = Double(hookahText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let b = Double(barText.replacingOccurrences(of: ",", with: ".")) ?? 0
        store.setRevenue(DayRevenue(hookah: h, bar: b), date: day)
    }

    private var revenueSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                moneyField("Кальянная", $hookahText)
                moneyField("Бар", $barText)
            }

            HStack(alignment: .firstTextBaseline) {
                Label("Итого за день", systemImage: "equal.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Money.grouped(revTotal)) ₽")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(revTotal > 0 ? Color.green : Color.secondary)
                    .contentTransition(.numericText())
            }
            .animation(.snappy, value: revTotal)

            HStack {
                Label("\(store.workedEmployees(date: day).count) на смене",
                      systemImage: "person.2.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("К выплате: \(Money.grouped(payout)) ₽")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .animation(.snappy, value: payout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func moneyField(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("0", text: text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, _ in commit() }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmployeeDayRow: View {
    @EnvironmentObject var store: Store
    let day: Date
    let employee: Employee

    private var shift: Shift { store.resolvedShift(employee: employee.id, date: day) }
    private var isWork: Bool { shift.kind.isWork }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isWork },
            set: { on in
                Haptics.select()
                withAnimation(.snappy) {
                    store.setShift(Shift(kind: on ? .work : .off), employee: employee.id, date: day)
                }
            }
        )) {
            HStack(spacing: 10) {
                Circle().fill(employee.color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(employee.name).font(.callout.weight(.medium))
                    Text(employee.role.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if isWork {
                    Text("полная")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(employee.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(employee.color.opacity(0.14), in: Capsule())
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isWork ? employee.color.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .animation(.snappy, value: isWork)
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
        #if os(macOS)
        .frame(width: 420)
        #else
        .frame(maxWidth: .infinity)
        #endif
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

// MARK: - Сводка месяца

/// Итоги месяца: выручка, смены, выплаты и разбивка по сотрудникам.
struct MonthSummarySheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    @State private var copied = false

    private var cal: Calendar { Calendar.current }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    private var rows: [EmployeePay] { store.payroll(forMonth: month) }
    private var payrollTotal: Double { rows.reduce(0) { $0 + $1.total } }
    private var revenue: Double { store.monthRevenue(month) }
    private var shifts: Int { rows.reduce(0) { $0 + $1.workDays } }
    private var premiums: Double { rows.reduce(0) { $0 + $1.premiumTotal } }
    private var fines: Double { rows.reduce(0) { $0 + $1.fineTotal } }

    /// Дни, в которые кто-то работал.
    private var workDays: Int {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return 0 }
        var count = 0
        var d = interval.start
        while d < interval.end {
            if !store.workedEmployees(date: d).isEmpty { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return count
    }

    private var avgPerDay: Double {
        workDays > 0 ? revenue / Double(workDays) : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Сводка месяца").font(.headline)
                    Text(monthTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyText()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.callout.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary.opacity(0.35), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Скопировать сводку текстом")

                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderless)
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    revenueCard
                    statsGrid
                    breakdown
                    employeesList
                }
                .padding(16)
            }
        }
        #if os(macOS)
        .frame(width: 470, height: 620)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .overlay(alignment: .bottom) {
            if copied {
                Label("Сводка скопирована", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: copied)
    }

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Выручка за месяц").font(.caption).foregroundStyle(.secondary)
            Text("\(Money.grouped(revenue)) ₽")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(colors: [.green, .accentColor],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.snappy, value: revenue)
            Text("Средняя выручка за рабочий день: \(Money.grouped(avgPerDay)) ₽")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: [Color.green.opacity(0.12), Color.accentColor.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            stat("Смен", "\(shifts)", icon: "calendar.badge.clock")
            stat("Рабочих дней", "\(workDays)", icon: "calendar")
            stat("К выплате", "\(Money.grouped(payrollTotal)) ₽", icon: "rublesign.circle")
            stat("Средняя за день", "\(Money.grouped(avgPerDay)) ₽", icon: "chart.line.uptrend.xyaxis")
        }
    }

    private func stat(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var breakdown: some View {
        if premiums > 0 || fines > 0 {
            HStack(spacing: 10) {
                if premiums > 0 {
                    Label("Премии +\(Money.grouped(premiums)) ₽", systemImage: "star.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                if fines > 0 {
                    Label("Штрафы −\(Money.grouped(fines)) ₽", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var employeesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("По сотрудникам")
                .font(.headline)
            ForEach(rows) { pay in
                HStack(spacing: 10) {
                    Circle().fill(pay.employee.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pay.employee.name).font(.callout.weight(.medium))
                        Text("\(pay.workDays) смен · база \(Money.grouped(pay.baseTotal)) ₽")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Text("\(Money.grouped(pay.total)) ₽")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(pay.total < 0 ? .red : .primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var summaryText: String {
        var text = "Turno — \(monthTitle)\n"
        text += "Выручка: \(Money.grouped(revenue)) ₽\n"
        text += "Смен: \(shifts) · рабочих дней: \(workDays)\n"
        text += "К выплате: \(Money.grouped(payrollTotal)) ₽\n"
        if premiums > 0 { text += "Премии: +\(Money.grouped(premiums)) ₽\n" }
        if fines > 0 { text += "Штрафы: −\(Money.grouped(fines)) ₽\n" }
        text += "\n"
        for pay in rows {
            text += "\(pay.employee.name): \(pay.workDays) смен — \(Money.grouped(pay.total)) ₽\n"
        }
        return text
    }

    private func copyText() {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(summaryText, forType: .string)
        #else
        UIPasteboard.general.string = summaryText
        #endif
        Haptics.success()
        withAnimation(.snappy) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.snappy) { copied = false }
        }
    }
}
