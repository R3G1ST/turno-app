import SwiftUI

// MARK: - Экран дня: работавшие + выручка + надбавки

struct DayView: View {
    @EnvironmentObject var store: Store
    @State private var day: Date = Calendar.current.startOfDay(for: Date())
    @State private var hookahText: String = ""
    @State private var barText: String = ""
    @State private var loadedFor: String = ""

    private var cal: Calendar { Calendar.current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                datePicker
                revenueCard
                bonusesCard
                workersCard
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .center)
        }
        .onAppear(perform: loadFields)
        .onChange(of: loadedFor) { _, _ in loadFields() }
        .onChange(of: day) { _, newValue in
            loadedFor = Keys.day(newValue)
        }
    }

    private func loadFields() {
        let rev = store.revenue(date: day)
        hookahText = rev.hookah == 0 ? "" : formattedInput(rev.hookah)
        barText = rev.bar == 0 ? "" : formattedInput(rev.bar)
        loadedFor = Keys.day(day)
    }

    private func formattedInput(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    // MARK: Выбор дня

    private var datePicker: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
            DatePicker("", selection: $day, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            Button("Сегодня") { day = cal.startOfDay(for: Date()) }
                .buttonStyle(.borderless)
            Spacer()
            let count = store.workedEmployees(date: day).count
            Label("\(count) на смене", systemImage: "person.2.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func shiftDay(_ delta: Int) {
        if let d = cal.date(byAdding: .day, value: delta, to: day) { day = d }
    }

    // MARK: Карточка выручки

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Выручка за день")
                .font(.headline)

            HStack(spacing: 14) {
                revenueField(title: "Кальянная", icon: "smoke", text: $hookahText)
                revenueField(title: "Бар", icon: "wineglass", text: $barText)
                totalBox
            }

            let passed = store.passedThresholds(date: day)
            if !passed.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Порог пройден — надбавка \(passed.map { Int($0.amount) }.map(String.init).joined(separator: " + ")) ₽ каждому на смене")
                        .font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func revenueField(title: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, newValue in
                    commitRevenue()
                }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private var totalBox: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label("Итого", systemImage: "equal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(store.revenue(date: day).total)) ₽")
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .frame(maxWidth: 220)
        .background(
            LinearGradient(colors: [.accentColor.opacity(0.18), .accentColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func commitRevenue() {
        let h = Double(hookahText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let b = Double(barText.replacingOccurrences(of: ",", with: ".")) ?? 0
        store.setRevenue(DayRevenue(hookah: h, bar: b), date: day)
    }

    // MARK: Надбавки

    private var bonusesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Надбавки за пороги выручки")
                .font(.headline)
            if store.data.thresholds.isEmpty {
                Text("Пороги не заданы — добавьте их в Настройках (⌘,).")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.data.thresholds.sorted { $0.revenueFrom < $1.revenueFrom }) { t in
                    let passed = t.enabled && store.revenue(date: day).total >= t.revenueFrom
                    HStack {
                        Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(passed ? .green : .secondary)
                        Text("Выручка ≥ \(Int(t.revenueFrom)) ₽")
                        Spacer()
                        Text("+\(Int(t.amount)) ₽")
                            .fontWeight(.semibold)
                            .foregroundStyle(passed ? .green : .secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Работавшие

    /// Сумма к выплате всем работникам смены за этот день.
    private var dayPayrollTotal: Double {
        let bonusEach = store.passedThresholds(date: day).reduce(0.0) { $0 + $1.amount }
        return store.workedEmployees(date: day).reduce(0.0) { sum, emp in
            let s = store.resolvedShift(employee: emp.id, date: day)
            return sum + (s.rateOverride ?? emp.defaultShiftRate) + bonusEach
        }
    }

    private var workersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Кто на смене")
                .font(.headline)
            let workers = store.workedEmployees(date: day)
            if workers.isEmpty {
                Text("В этот день никто не работает.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let bonuses = store.passedThresholds(date: day)
                let bonusEach = bonuses.reduce(0.0) { $0 + $1.amount }
                ForEach(workers) { emp in
                    let shift = store.resolvedShift(employee: emp.id, date: day)
                    HStack {
                        Image(systemName: emp.role.icon).foregroundStyle(emp.role.color)
                        Text(emp.name).fontWeight(.medium)
                        Spacer()
                        Text(shift.kind.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(shift.kind.color.opacity(0.2), in: Capsule())
                        let base = shift.rateOverride ?? emp.defaultShiftRate
                        Text("\(Int(base + bonusEach)) ₽")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    Spacer()
                    Text("К выплате за день:")
                        .fontWeight(.medium)
                    Text("\(Int(dayPayrollTotal)) ₽")
                        .fontWeight(.bold).monospacedDigit()
                }
                .font(.callout)
                .padding(.top, 6)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
