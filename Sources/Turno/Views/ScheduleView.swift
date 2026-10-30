import SwiftUI

// MARK: - Главный экран: месячная сетка графика

struct ScheduleView: View {
    @EnvironmentObject var store: Store
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date?

    private var cal: Calendar { Calendar.current }
    private var daysInMonth: [Date] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let count = Int(interval.duration / 86400)
        return (0..<count).compactMap {
            cal.date(byAdding: .day, value: $0, to: interval.start)
        }
    }
    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            gridScroll
        }
    }

    // MARK: Шапка с переключением месяца

    private var header: some View {
        HStack(spacing: 12) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(width: 200)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
            Button("Сегодня") { month = cal.startOfDay(for: Date()) }
                .buttonStyle(.borderless)
                .font(.callout)

            Spacer()

            legend
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([ShiftKind.morning, .evening, .full, .off]) { kind in
                HStack(spacing: 5) {
                    Circle().fill(kind.color).frame(width: 10, height: 10)
                    Text(kind.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: month) { month = d }
    }

    // MARK: Сетка

    private var gridScroll: some View {
        let employees = store.data.employees.filter(\.active)
        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                dayHeaderRow
                Divider()
                ForEach(employees) { emp in
                    employeeRow(emp)
                    Divider()
                }
            }
        }
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Сотрудник")
                .font(.caption.weight(.semibold))
                .frame(width: 180, alignment: .leading)
                .padding(.leading, 14)
            ForEach(daysInMonth, id: \.self) { d in
                let wd = cal.component(.weekday, from: d)
                let isWeekend = wd == 1 || wd == 7
                VStack(spacing: 1) {
                    Text(weekdayInitial(d))
                        .font(.system(size: 9))
                        .foregroundStyle(isWeekend ? .red.opacity(0.8) : .secondary)
                    Text("\(cal.component(.day, from: d))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isWeekend ? .red : .primary)
                }
                .frame(width: 36, height: 34)
                .background(isWeekend ? Color.red.opacity(0.05) : .clear)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func weekdayInitial(_ d: Date) -> String {
        let wd = cal.component(.weekday, from: d)
        return ["В", "П", "В", "С", "Ч", "П", "С"][wd - 1]
    }

    private func employeeRow(_ emp: Employee) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: emp.role.icon)
                    .foregroundStyle(emp.role.color)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text(emp.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(emp.role.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, alignment: .leading)
            .padding(.leading, 14)
            .contextMenu {
                patternMenu(emp)
                Divider()
                Button("Очистить месяц") { clearMonth(emp) }
            }

            ForEach(daysInMonth, id: \.self) { d in
                cell(emp, d)
            }
        }
        .frame(height: 40)
    }

    private func cell(_ emp: Employee, _ d: Date) -> some View {
        let shift = store.resolvedShift(employee: emp.id, date: d)
        let wd = cal.component(.weekday, from: d)
        let isWeekend = wd == 1 || wd == 7
        return Button {
            cycleShift(emp, d)
        } label: {
            Text(shift.kind.short)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(shift.kind.isWork ? .white : .secondary)
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(shift.kind.isWork
                             ? AnyShapeStyle(shift.kind.color)
                             : AnyShapeStyle(shift.kind.color.opacity(isWeekend ? 0.10 : 0.18)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selectedDay == d ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach([ShiftKind.morning, .evening, .full, .off]) { kind in
                Button {
                    store.setShift(Shift(kind: kind), employee: emp.id, date: d)
                } label: {
                    Label(kind.rawValue, systemImage: kind == .off ? "moon" : "sun.max")
                }
            }
            Divider()
            Button("Скопировать неделю вправо") { copyWeekRight(emp, d) }
        }
        .help("\(emp.name) — \(dayString(d)) — \(shift.kind.rawValue)")
    }

    private func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: d)
    }

    // MARK: Действия

    /// Клик по ячейке: П → У → В → П … (выходной ставится последним).
    private func cycleShift(_ emp: Employee, _ d: Date) {
        let cur = store.resolvedShift(employee: emp.id, date: d).kind
        let next: ShiftKind
        switch cur {
        case .full: next = .morning
        case .morning: next = .evening
        case .evening: next = .off
        case .off: next = .full
        }
        store.setShift(Shift(kind: next), employee: emp.id, date: d)
    }

    @ViewBuilder
    private func patternMenu(_ emp: Employee) -> some View {
        Menu("Заполнить шаблон") {
            ForEach(FillPattern.allCases) { p in
                Button(p.rawValue) { fill(emp, pattern: p) }
            }
        }
        Menu("Копировать") {
            ForEach(FillPattern.allCases.filter { $0 != .allOff && $0 != .allFull }) { p in
                Button("Прошлая неделя — \(p.rawValue)") { fill(emp, pattern: p) }
            }
        }
    }

    private func fill(_ emp: Employee, pattern: FillPattern) {
        for (i, d) in daysInMonth.enumerated() {
            let kind: ShiftKind
            switch pattern {
            case .allOff: kind = .off
            case .allFull: kind = .full
            default:
                let cycle = pattern.workDays! + pattern.restDays!
                let phase = i % cycle
                kind = phase < pattern.workDays! ? .full : .off
            }
            store.setShift(Shift(kind: kind), employee: emp.id, date: d)
        }
        store.saveNow()
    }

    private func clearMonth(_ emp: Employee) {
        for d in daysInMonth {
            store.setShift(Shift(kind: .off), employee: emp.id, date: d)
        }
        store.saveNow()
    }

    /// Копирует 7 дней недели, в которую попадает клик, в следующую неделю.
    private func copyWeekRight(_ emp: Employee, _ d: Date) {
        guard let weekStart = cal.dateInterval(of: .weekOfMonth, for: d)?.start else { return }
        for offset in 0..<7 {
            guard let src = cal.date(byAdding: .day, value: offset, to: weekStart),
                  let dst = cal.date(byAdding: .day, value: offset + 7, to: weekStart)
            else { continue }
            store.setShift(store.resolvedShift(employee: emp.id, date: src), employee: emp.id, date: dst)
        }
        store.saveNow()
    }
}
