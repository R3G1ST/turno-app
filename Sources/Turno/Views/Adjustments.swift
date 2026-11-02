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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Редактирование премии" : "Новая премия")
                        .font(.headline)
                    Text("Разовое начисление сотруднику")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                #if os(iOS)
                Button("Готово") { dismiss() }
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderless)
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Сотрудник", selection: $employeeID) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.data.employees) { emp in
                            Text("\(emp.name) (\(emp.role.rawValue))").tag(Optional(emp.id))
                        }
                    }

                    HStack {
                        TextField("Сумма, ₽", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                        Text("₽").foregroundStyle(.secondary)
                    }

                    DatePicker("Дата", selection: $date, displayedComponents: .date)

                    TextField("За что", text: $note, prompt: Text("например: хорошие отзывы гостей"))
                        .textFieldStyle(.roundedBorder)
                }
                .padding(18)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Начислить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(employeeID == nil || amount <= 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        #if os(macOS)
        .frame(width: 420)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Haptics.success()
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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Редактирование штрафа" : "Новый штраф")
                        .font(.headline)
                    Text("Удержание можно разбить на несколько месяцев")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                #if os(iOS)
                Button("Готово") { dismiss() }
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderless)
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Сотрудник", selection: $employeeID) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.data.employees) { emp in
                            Text("\(emp.name) (\(emp.role.rawValue))").tag(Optional(emp.id))
                        }
                    }

                    HStack {
                        TextField("Сумма, ₽", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                        Text("₽").foregroundStyle(.secondary)
                    }

                    VStack(spacing: 6) {
                        HStack {
                            Text("Разбить на месяцев")
                                .font(.callout)
                            Spacer()
                            Stepper(value: $months, in: 1...24) {
                                Text("\(months)")
                                    .frame(width: 24)
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                        }
                        if months > 1 && amount > 0 {
                            HStack {
                                Text("По \(Money.grouped(amount / Double(months))) ₽ в месяц")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    DatePicker("Месяц начала", selection: monthBinding, displayedComponents: .date)

                    TextField("Причина", text: $note, prompt: Text("например: порча инвентаря"))
                        .textFieldStyle(.roundedBorder)

                    Label("Удержание начнётся с \(startMonthKey.replacingOccurrences(of: "-", with: ".")) и продолжится \(months) мес.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Наложить штраф") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(employeeID == nil || amount <= 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Haptics.success()
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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Штрафы и премии")
                        .font(.headline)
                    Text("Все начисления по сотрудникам")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #if os(macOS)
        .frame(width: 600, height: 520)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .sheet(item: $editingPremium) { p in
            PremiumSheet(month: month, existing: p).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
        .sheet(item: $editingFine) { f in
            FineSheet(month: month, existing: f).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
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
                Label(emptyText, systemImage: "tray")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                content()
            }
        }
    }

    @ViewBuilder
    private func rowActions(edit: @escaping () -> Void,
                            delete: @escaping () -> Void) -> some View {
        #if os(iOS)
        Menu {
            Button { edit() } label: { Label("Изменить", systemImage: "pencil") }
            Button(role: .destructive) { delete() } label: { Label("Удалить", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        #else
        HStack(spacing: 2) {
            Button(action: edit) { Image(systemName: "pencil").frame(width: 24, height: 24) }
                .buttonStyle(.borderless)
                .help("Изменить")
            Button(action: delete) { Image(systemName: "trash").frame(width: 24, height: 24) }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Удалить")
        }
        #endif
    }

    private func premiumRow(_ p: Premium) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .frame(width: 28, height: 28)
                .background(Color.yellow.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(p.note).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(store.employeeName(p.employeeID)) · \(dateStr(p.date))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text("+\(Money.grouped(p.amount)) ₽")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            rowActions(edit: { editingPremium = p },
                       delete: { deletePremiumTarget = p })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fineRow(_ f: Fine) -> some View {
        let per = f.monthsCount > 0 ? f.totalAmount / Double(f.monthsCount) : f.totalAmount
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(Color.red.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(f.note).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(store.employeeName(f.employeeID)) · с \(f.startMonth.replacingOccurrences(of: "-", with: ".")) · \(f.monthsCount) мес. · \(Money.grouped(per)) ₽/мес")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text("−\(Money.grouped(f.totalAmount)) ₽")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            rowActions(edit: { editingFine = f },
                       delete: { deleteFineTarget = f })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}
