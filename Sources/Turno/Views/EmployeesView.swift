import SwiftUI

// MARK: - Сотрудники

struct EmployeesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Employee?
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Сотрудники")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showAdd = true
                } label: { Label("Добавить", systemImage: "plus") }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.data.employees) { emp in
                        card(emp)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720)
            }
        }
        .sheet(isPresented: $showAdd) {
            EmployeeSheet(employee: nil)
        }
        .sheet(item: $editing) { emp in
            EmployeeSheet(employee: emp)
        }
    }

    private func card(_ emp: Employee) -> some View {
        HStack {
            Image(systemName: emp.role.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(emp.color.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading) {
                Text(emp.name).fontWeight(.medium)
                Text(emp.role.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(emp.defaultShiftRate)) ₽/смена")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            Toggle("", isOn: $store.data.employees[store.data.employees.firstIndex(where: { $0.id == emp.id })!].active)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Активен — показывать в графике")
            Button {
                editing = emp
            } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .opacity(emp.active ? 1 : 0.55)
    }
}

// MARK: - Лист добавления/редактирования

struct EmployeeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let employee: Employee?

    @State private var name = ""
    @State private var role: Role = .hookah
    @State private var rate = "2300"
    @State private var active = true
    @State private var colorHex: UInt32 = Palette.colors[0].hex

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(employee == nil ? "Новый сотрудник" : "Редактирование")
                .font(.headline)

            TextField("Имя", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Роль", selection: $role) {
                ForEach(Role.allCases) { r in
                    Label(r.rawValue, systemImage: r.icon).tag(r)
                }
            }

            HStack {
                TextField("Ставка за смену, ₽", text: $rate)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text("₽").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Цвет сотрудника")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Palette.colors, id: \.hex) { c in
                        Button {
                            colorHex = c.hex
                        } label: {
                            Circle()
                                .fill(Palette.color(c.hex))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().strokeBorder(Color.primary, lineWidth: colorHex == c.hex ? 2.5 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(c.name)
                    }
                }
            }

            Toggle("Активен", isOn: $active)

            HStack {
                Spacer()
                if employee != nil {
                    Button("Удалить", role: .destructive) {
                        store.data.employees.removeAll { $0.id == employee!.id }
                        store.saveNow()
                        dismiss()
                    }
                }
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
#if os(macOS)
        .frame(width: 380)
#else
        .frame(maxWidth: .infinity)
#endif
        .onAppear {
            if let e = employee {
                name = e.name; role = e.role; rate = String(Int(e.defaultShiftRate)); active = e.active
                colorHex = e.colorHex ?? Palette.colors[0].hex
            }
        }
    }

    private func save() {
        let r = Double(rate.replacingOccurrences(of: ",", with: ".")) ?? 0
        if var e = employee {
            e.name = name.trimmingCharacters(in: .whitespaces)
            e.role = role
            e.defaultShiftRate = r
            e.active = active
            e.colorHex = colorHex
            if let i = store.data.employees.firstIndex(where: { $0.id == e.id }) {
                store.data.employees[i] = e
            }
        } else {
            store.data.employees.append(
                Employee(name: name.trimmingCharacters(in: .whitespaces), role: role, defaultShiftRate: r, active: active, colorHex: colorHex)
            )
        }
        store.saveNow()
        dismiss()
    }
}
