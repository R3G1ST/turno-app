import SwiftUI
import AppKit

// MARK: - Лист: добавить премию

struct PremiumSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    @State private var employeeID: UUID?
    @State private var amountText = ""
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Новая премия")
                .font(.headline)

            Picker("Сотрудник", selection: $employeeID) {
                Text("—").tag(UUID?.none)
                ForEach(store.data.employees.filter(\.active)) { emp in
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
                Button("Начислить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(employeeID == nil || (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
            }
        }
        .padding(22)
        .frame(width: 400)
        .onAppear {
            if employeeID == nil { employeeID = store.data.employees.filter(\.active).first?.id }
        }
    }

    private func save() {
        guard let id = employeeID,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0
        else { return }
        store.data.premiums.append(
            Premium(employeeID: id, amount: amount, date: date,
                    note: note.isEmpty ? "Премия" : note)
        )
        store.saveNow()
        dismiss()
    }
}

// MARK: - Лист: добавить штраф (с разбивкой на месяцы)

struct FineSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let month: Date

    @State private var employeeID: UUID?
    @State private var amountText = ""
    @State private var months = 1
    @State private var note = ""

    private var amount: Double { Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Новый штраф")
                .font(.headline)

            Picker("Сотрудник", selection: $employeeID) {
                Text("—").tag(UUID?.none)
                ForEach(store.data.employees.filter(\.active)) { emp in
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

            TextField("Причина", text: $note, prompt: Text("например: порча инвентаря"))
                .textFieldStyle(.roundedBorder)

            Text("Удержание начнётся с \(store.monthKey(month).replacingOccurrences(of: "-", with: ".")) и продолжится \(months) мес.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Наложить штраф") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(employeeID == nil || amount <= 0)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear {
            if employeeID == nil { employeeID = store.data.employees.filter(\.active).first?.id }
        }
    }

    private func save() {
        guard let id = employeeID, amount > 0 else { return }
        store.data.fines.append(
            Fine(employeeID: id, totalAmount: amount,
                 note: note.isEmpty ? "Штраф" : note,
                 startMonth: store.monthKey(month), monthsCount: months)
        )
        store.saveNow()
        dismiss()
    }
}
