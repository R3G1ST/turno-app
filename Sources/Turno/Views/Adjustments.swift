import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Лист: добавить / редактировать премию

struct PremiumSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date
    /// Если передана существующая премия — режим редактирования.
    var existing: Premium? = nil

    @State private var employeeID: UUID?
    @State private var amountText = ""
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var note = ""

    private var isEditing: Bool { existing != nil }
    private var amount: Double { Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Редактирование премии" : "Новая премия")
                .font(.headline)

            Picker("Сотрудник", selection: $employeeID) {
                Text("—").tag(UUID?.none)
                ForEach(store.data.employees) { emp in
                    Text("\(emp.name) (\(emp.role.rawValue))").tag(Optional(emp.id))
                }
            }

            HStack {
                TextField("Сумма, ₽", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text("₽").foregroundStyle(.secondary)
            }

            DatePicker("Дата", selection: $date, displayedComponents: .date)

            TextField("За что", text: $note, prompt: Text("например: хорошие отзывы гостей"))
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Начислить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(employeeID == nil || amount <= 0)
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 400)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .onAppear {
            if let p = existing {
                employeeID = p.employeeID
                amountText = String(Int(p.amount))
                date = p.date
                note = p.note == "Премия" ? "" : p.note
            } else if employeeID == nil {
                employeeID = store.data.employees.first(where: \.active)?.id
            }
        }
    }

    private func save() {
        guard let id = employeeID, amount > 0 else { return }
        var p = existing ?? Premium(employeeID: id, amount: amount, date: date,
                                    note: note.isEmpty ? "Премия" : note)
        p.employeeID = id
        p.amount = amount
        p.date = date
        p.note = note.isEmpty ? "Премия" : note
        store.upsertPremium(p)
        dismiss()
    }
}

// MARK: - Лист: добавить / редактировать штраф (с разбивкой на месяцы)

struct FineSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date
    /// Если передан существующий штраф — режим редактирования.
    var existing: Fine? = nil

    @State private var employeeID: UUID?
    @State private var amountText = ""
    @State private var months = 1
    @State private var note = ""
    @State private var startMonthKey = ""

    private var isEditing: Bool { existing != nil }
    private var amount: Double { Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Редактирование штрафа" : "Новый штраф")
                .font(.headline)

            Picker("Сотрудник", selection: $employeeID) {
                Text("—").tag(UUID?.none)
                ForEach(store.data.employees) { emp in
                    Text("\(emp.name) (\(emp.role.rawValue))").tag(Optional(emp.id))
                }
            }

            HStack {
                TextField("Сумма, ₽", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text("₽").foregroundStyle(.secondary)
            }

            HStack {
                Text("Разбить на месяцев")
                Stepper(value: $months, in: 1...24) {
                    Text("\(months)")
                        .frame(width: 24)
                        .font(.headline)
                }
                Spacer()
                if months > 1 && amount > 0 {
                    Text("\(Int((amount / Double(months)).rounded())) ₽/мес")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            DatePicker("Месяц начала", selection: monthBinding, displayedComponents: .date)

            TextField("Причина", text: $note, prompt: Text("например: порча инвентаря"))
                .textFieldStyle(.roundedBorder)

            Text("Удержание начнётся с \(startMonthKey.replacingOccurrences(of: "-", with: ".")) и продолжится \(months) мес.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Наложить штраф") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(employeeID == nil || amount <= 0)
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 440)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .onAppear {
            if let f = existing {
                employeeID = f.employeeID
                amountText = String(Int(f.totalAmount))
                months = f.monthsCount
                note = f.note == "Штраф" ? "" : f.note
                startMonthKey = f.startMonth
            } else {
                if employeeID == nil { employeeID = store.data.employees.first(where: \.active)?.id }
                startMonthKey = store.monthKey(month)
            }
        }
    }

    /// DatePicker привязан к 1-му числу месяца и пишет ключ "yyyy-MM".
    private var monthBinding: Binding<Date> {
        Binding(
            get: { store.monthDate(startMonthKey) ?? Date() },
            set: { startMonthKey = store.monthKey($0) }
        )
    }

    private func save() {
        guard let id = employeeID, amount > 0 else { return }
        var f = existing ?? Fine(employeeID: id, totalAmount: amount,
                                 note: note.isEmpty ? "Штраф" : note,
                                 startMonth: startMonthKey, monthsCount: months)
        f.employeeID = id
        f.totalAmount = amount
        f.note = note.isEmpty ? "Штраф" : note
        f.startMonth = startMonthKey
        f.monthsCount = months
        store.upsertFine(f)
        dismiss()
    }
}

// MARK: - Окно управления: все штрафы и премии

struct AdjustmentsManager: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    @State private var editingPremium: Premium?
    @State private var editingFine: Fine?
    @State private var deletePremiumTarget: Premium?
    @State private var deleteFineTarget: Fine?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Штрафы и премии")
                    .font(.headline)
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    block("Премии", isEmpty: store.data.premiums.isEmpty,
                          emptyText: "Премий пока нет") {
                        ForEach(store.allPremiums()) { p in premiumRow(p) }
                    }
                    block("Штрафы", isEmpty: store.data.fines.isEmpty,
                          emptyText: "Штрафов пока нет") {
                        ForEach(store.allFines()) { f in fineRow(f) }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #if os(macOS)
        .frame(width: 600, height: 500)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .sheet(item: $editingPremium) { p in
            PremiumSheet(month: month, existing: p).environmentObject(store)
        }
        .sheet(item: $editingFine) { f in
            FineSheet(month: month, existing: f).environmentObject(store)
        }
        .confirmationDialog("Удалить премию «\(deletePremiumTarget?.note ?? "")»?",
                            isPresented: Binding(get: { deletePremiumTarget != nil },
                                                 set: { if !$0 { deletePremiumTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let p = deletePremiumTarget { store.deletePremium(p) }
                deletePremiumTarget = nil
            }
            Button("Отмена", role: .cancel) { deletePremiumTarget = nil }
        }
        .confirmationDialog("Удалить штраф «\(deleteFineTarget?.note ?? "")» по всем месяцам?",
                            isPresented: Binding(get: { deleteFineTarget != nil },
                                                 set: { if !$0 { deleteFineTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let f = deleteFineTarget { store.deleteFine(f) }
                deleteFineTarget = nil
            }
            Button("Отмена", role: .cancel) { deleteFineTarget = nil }
        }
    }

    @ViewBuilder
    private func block(_ title: String, isEmpty: Bool, emptyText: String,
                       @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            if isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            } else {
                content()
            }
        }
    }

    private func premiumRow(_ p: Premium) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(p.note).font(.callout).lineLimit(1)
                Text("\(store.employeeName(p.employeeID)) · \(dateStr(p.date))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(Int(p.amount)) ₽")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.green)
            Button { editingPremium = p } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
            Button { deletePremiumTarget = p } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func fineRow(_ f: Fine) -> some View {
        let per = f.monthsCount > 0 ? Int((f.totalAmount / Double(f.monthsCount)).rounded()) : Int(f.totalAmount)
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
            VStack(alignment: .leading) {
                Text(f.note).font(.callout).lineLimit(1)
                Text("\(store.employeeName(f.employeeID)) · с \(f.startMonth.replacingOccurrences(of: "-", with: ".")) · \(f.monthsCount) мес. · \(per) ₽/мес")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("−\(Int(f.totalAmount)) ₽")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
            Button { editingFine = f } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
            Button { deleteFineTarget = f } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}
