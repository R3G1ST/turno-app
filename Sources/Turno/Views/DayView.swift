import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Экран дня: работавшие + выручка + надбавки

struct DayView: View {
    @EnvironmentObject var store: Store
    @State private var day: Date = Calendar.current.startOfDay(for: Date())
    @State private var hookahText: String = ""
    @State private var barText: String = ""
    @State private var loadedFor: String = ""
    @FocusState private var amountFocused: Bool

    private var cal: Calendar { Calendar.current }

    /// Отступы страницы: на телефоне компактнее.
    private var pagePadding: CGFloat {
#if os(iOS)
        14
#else
        20
#endif
    }

    /// Ширина колонки суммы в карточке «кто на смене».
    private var payWidth: CGFloat {
#if os(iOS)
        74
#else
        90
#endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                datePicker
                revenueCard
                bonusesCard
                workersCard
            }
            .padding(pagePadding)
            .frame(maxWidth: 900, alignment: .center)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { amountFocused = false }
            }
        }
        #endif
        .onAppear(perform: loadFields)
        .onChange(of: loadedFor) { _, _ in loadFields() }
        .onChange(of: day) { _, newValue in
            loadedFor = Keys.day(newValue)
        }
        .animation(.snappy, value: day)
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
        HStack(spacing: 8) {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PressableButtonStyle())

            DatePicker("", selection: $day, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()

            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PressableButtonStyle())

#if os(iOS)
            Button {
                Haptics.tap()
                withAnimation(.snappy) { day = cal.startOfDay(for: Date()) }
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.body.weight(.medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PressableButtonStyle())
#else
            Button("Сегодня") {
                withAnimation(.snappy) { day = cal.startOfDay(for: Date()) }
            }
            .buttonStyle(.borderless)
#endif
            Spacer(minLength: 4)
            #if os(macOS)
            let count = store.workedEmployees(date: day).count
            Label("\(count) на смене", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func shiftDay(_ delta: Int) {
        guard let d = cal.date(byAdding: .day, value: delta, to: day) else { return }
        Haptics.select()
        withAnimation(.snappy) { day = d }
    }

    // MARK: Карточка выручки

    private var revenueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Выручка за день")
                    .font(.headline)
                Spacer()
                if store.revenue(date: day).total > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            #if os(iOS)
            // На телефоне два поля в ряд, итог — отдельной строкой во всю ширину.
            HStack(spacing: 10) {
                revenueField(title: "Кальянная", icon: "smoke", text: $hookahText)
                revenueField(title: "Бар", icon: "wineglass", text: $barText)
            }
            totalBox
            #else
            HStack(spacing: 14) {
                revenueField(title: "Кальянная", icon: "smoke", text: $hookahText)
                revenueField(title: "Бар", icon: "wineglass", text: $barText)
                totalBox
            }
            #endif

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
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: store.revenue(date: day).total)
    }

    private func revenueField(title: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                #endif
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, _ in
                    commitRevenue()
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var totalBox: some View {
        let total = store.revenue(date: day).total
        #if os(iOS)
        return HStack(alignment: .firstTextBaseline) {
            Label("Итого", systemImage: "equal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(Money.grouped(total)) ₽")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.accentColor.opacity(0.18), .accentColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .animation(.snappy, value: total)
        #else
        return VStack(alignment: .trailing, spacing: 6) {
            Label("Итого", systemImage: "equal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Money.grouped(total)) ₽")
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .frame(maxWidth: 220)
        .background(
            LinearGradient(colors: [.accentColor.opacity(0.18), .accentColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .animation(.snappy, value: total)
        #endif
    }

    private func commitRevenue() {
        let h = Double(hookahText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let b = Double(barText.replacingOccurrences(of: ",", with: ".")) ?? 0
        store.setRevenue(DayRevenue(hookah: h, bar: b), date: day)
    }

    // MARK: Надбавки

    private var bonusesCard: some View {
        let total = store.revenue(date: day).total
        let sorted = store.data.thresholds.sorted { $0.revenueFrom < $1.revenueFrom }
        let next = sorted.first { $0.enabled && $0.revenueFrom > total }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Надбавки за пороги")
                    .font(.headline)
                Spacer(minLength: 6)
                if let next, total > 0 {
                    Text("до +\(Money.grouped(next.amount)) ₽ · осталось \(Money.grouped(next.revenueFrom - total)) ₽")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if sorted.isEmpty {
                Text("Пороги не заданы — добавьте их в Настройках.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(sorted) { t in
                    let passed = t.enabled && total >= t.revenueFrom
                    let fraction = t.revenueFrom > 0
                        ? min(1, max(0, total / t.revenueFrom)) : (passed ? 1 : 0)
                    VStack(spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                                .font(.callout)
                                .foregroundStyle(passed ? .green : .secondary)
                            Text("Выручка ≥ \(Money.grouped(t.revenueFrom)) ₽")
                                .font(.callout)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if !t.enabled {
                                Text("выкл.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("+\(Money.grouped(t.amount)) ₽")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(passed ? .green : .secondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule()
                                    .fill(passed ? AnyShapeStyle(Color.green)
                                          : AnyShapeStyle(Color.accentColor.opacity(0.5)))
                                    .frame(width: max(3, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 4)
                        .opacity(t.enabled ? 1 : 0.35)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: total)
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
            HStack {
                Text("Кто на смене")
                    .font(.headline)
                Spacer()
                let count = store.workedEmployees(date: day).count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
            }
            let workers = store.workedEmployees(date: day)
            if workers.isEmpty {
                Label("В этот день никто не работает", systemImage: "moon.zzz")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let bonuses = store.passedThresholds(date: day)
                let bonusEach = bonuses.reduce(0.0) { $0 + $1.amount }
                ForEach(workers) { emp in
                    let shift = store.resolvedShift(employee: emp.id, date: day)
                    HStack(spacing: 10) {
                        Image(systemName: emp.role.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(emp.color.gradient,
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(emp.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(shift.kind.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if bonusEach > 0 {
                            Text("+\(Money.grouped(bonusEach))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.green)
                                .lineLimit(1)
                        }
                        let base = shift.rateOverride ?? emp.defaultShiftRate
                        Text("\(Money.grouped(base + bonusEach)) ₽")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: payWidth, alignment: .trailing)
                    }
                    .padding(.vertical, 3)

                    if emp.id != workers.last?.id {
                        Divider().opacity(0.5)
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("К выплате за день")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Money.grouped(dayPayrollTotal)) ₽")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(colors: [.accentColor, .purple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .contentTransition(.numericText())
                }
                .animation(.snappy, value: dayPayrollTotal)
            }
        }
        .padding(16)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: day)
    }
}
