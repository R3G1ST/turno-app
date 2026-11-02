import SwiftUI

// MARK: - Сотрудники

struct EmployeesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Employee?
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Сотрудники")
                    .font(.title3.weight(.bold))
                let activeCount = store.data.employees.filter(\.active).count
                Text("\(activeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                Spacer()

                Button {
                    Haptics.tap()
                    showAdd = true
                } label: {
                    Label("Добавить", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)
            Divider()

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(store.data.employees) { emp in
                        card(emp)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    if store.data.employees.isEmpty {
                        ContentUnavailableView("Пока никого нет",
                                               systemImage: "person.2",
                                               description: Text("Нажмите «Добавить», чтобы завести сотрудника."))
                            .padding(.top, 40)
                    }
                }
                .padding(listPadding)
                .frame(maxWidth: 720)
                .animation(.snappy, value: store.data.employees.count)
            }
        }
        .sheet(isPresented: $showAdd) {
            EmployeeSheet(employee: nil)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
        .sheet(item: $editing) { emp in
            EmployeeSheet(employee: emp)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
    }

    /// Отступы списка: на телефоне компактнее.
    private var listPadding: CGFloat {
        #if os(iOS)
        14
        #else
        20
        #endif
    }

    private func card(_ emp: Employee) -> some View {
        HStack(spacing: 12) {
            Image(systemName: emp.role.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(emp.color.gradient,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(emp.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(emp.role.rawValue)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(Money.grouped(emp.defaultShiftRate)) ₽/смена")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: activeBinding(emp))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Активен — показывать в графике")

            Button {
                Haptics.tap()
                editing = emp
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Редактировать")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(emp.active ? emp.color.opacity(0.20) : Color.clear, lineWidth: 1)
        )
        .opacity(emp.active ? 1 : 0.55)
        .animation(.snappy, value: emp.active)
    }

    /// Безопасная привязка активности: не падает, если список изменился,
    /// и всегда сохраняет данные.
    private func activeBinding(_ emp: Employee) -> Binding<Bool> {
        Binding(
            get: { store.data.employees.first(where: { $0.id == emp.id })?.active ?? false },
            set: { newValue in
                guard let i = store.data.employees.firstIndex(where: { $0.id == emp.id }) else { return }
                Haptics.select()
                withAnimation(.snappy) { store.data.employees[i].active = newValue }
                store.saveNow()
            }
        )
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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(employee == nil ? "Новый сотрудник" : "Редактирование")
                        .font(.headline)
                    Text("Ставка и цвет применяются ко всем сменам")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Имя").font(.caption).foregroundStyle(.secondary)
                        TextField("Например, Руслан", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Роль").font(.caption).foregroundStyle(.secondary)
                        Picker("Роль", selection: $role) {
                            ForEach(Role.allCases) { r in
                                Label(r.rawValue, systemImage: r.icon).tag(r)
                            }
                        }
                        .labelsHidden()
                        #if os(iOS)
                        .pickerStyle(.menu)
                        #else
                        .pickerStyle(.segmented)
                        #endif
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ставка за смену").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("2300", text: $rate)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                            Text("₽").foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Цвет сотрудника")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)],
                                  spacing: 8) {
                            ForEach(Palette.colors, id: \.hex) { c in
                                Button {
                                    Haptics.select()
                                    withAnimation(.snappy) { colorHex = c.hex }
                                } label: {
                                    Circle()
                                        .fill(Palette.color(c.hex))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle().strokeBorder(Color.primary,
                                                                  lineWidth: colorHex == c.hex ? 2.5 : 0)
                                        )
                                        .scaleEffect(colorHex == c.hex ? 1.08 : 1)
                                }
                                .buttonStyle(PressableButtonStyle())
                                .help(c.name)
                            }
                        }
                    }

                    Toggle("Активен — показывать в графике", isOn: $active)
                        .font(.callout)
                        .onChange(of: active) { _, _ in Haptics.select() }
                }
                .padding(18)
            }

            Divider()

            HStack(spacing: 10) {
                if employee != nil {
                    Button(role: .destructive) {
                        if let e = employee {
                            Haptics.warning()
                            store.data.employees.removeAll { $0.id == e.id }
                            store.saveNow()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Удалить сотрудника")
                }
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        #if os(macOS)
        .frame(width: 400)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Haptics.success()
        dismiss()
    }
}
