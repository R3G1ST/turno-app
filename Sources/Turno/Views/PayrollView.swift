import SwiftUI
#if canImport(AppKit)
import AppKit
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Зарплата за месяц + экспорт PDF/CSV

struct PayrollView: View {
    @EnvironmentObject var store: Store
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var monthInitialized = false
    @State private var expanded: UUID?
    @State private var showPremium = false
    @State private var showFine = false
    @State private var showManager = false
    @State private var editingPremium: Premium?
    @State private var editingFine: Fine?
    @State private var deleteFineTarget: Fine?
    @State private var copyFlash = false

    private var cal: Calendar { Calendar.current }
    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }
    private var rows: [EmployeePay] { store.payroll(forMonth: month) }
    /// Ширина колонки суммы: на телефоне уже, чтобы влезали заметки и кнопки.
    private var amountWidth: CGFloat {
#if os(iOS)
        66
#else
        90
#endif
    }
    private var grandTotal: Double { rows.reduce(0) { $0 + $1.total } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .overlay(alignment: .top) {
            if copyFlash {
                Label("Ведомость скопирована", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.snappy, value: copyFlash)
        .sheet(isPresented: $showManager) {
            AdjustmentsManager(month: month).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
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
        .onAppear {
            // Стартуем на месяце с последними данными (см. ScheduleView).
            if !monthInitialized {
                monthInitialized = true
                month = store.lastActiveMonth
            }
        }
    }

    private var header: some View {
#if os(iOS)
        compactHeader
#else
        macHeader
#endif
    }

    /// Компактная шапка под телефон: месяц, свайп по списку, действия капсулами.
    private var compactHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PressableButtonStyle())

                Text(monthTitle)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .contentTransition(.interpolate)

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PressableButtonStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    actionChip("Премия", "star") { showPremium = true }
                    actionChip("Штраф", "exclamationmark.octagon") { showFine = true }
                    actionChip("Начисления", "list.bullet.rectangle") { showManager = true }
                    actionChip("Текст", "doc.on.doc") { copyPayrollText() }
                    actionChip("CSV", "tablecells") { exportCSV() }
                    actionChip("PDF", "doc.richtext") { exportPDF() }
                    actionChip("Печать", "printer") { printPDF() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showPremium) {
            PremiumSheet(month: month).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
        .sheet(isPresented: $showFine) {
            FineSheet(month: month).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
    }

    private func actionChip(_ title: String, _ icon: String,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.35), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var macHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
            Text(monthTitle).font(.title3.weight(.semibold)).frame(width: 180)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            Spacer()
            Button {
                showPremium = true
            } label: { Label("Премия", systemImage: "star") }
            Button {
                showFine = true
            } label: { Label("Штраф", systemImage: "exclamationmark.octagon") }
            Button {
                showManager = true
            } label: { Label("Все начисления", systemImage: "list.bullet.rectangle") }
            Button {
                copyPayrollText()
            } label: { Image(systemName: "doc.on.doc") }
                .help("Скопировать ведомость текстом")
            Button {
                exportCSV()
            } label: { Label("CSV", systemImage: "tablecells") }
            Button {
                exportPDF()
            } label: { Label("PDF", systemImage: "doc.richtext") }
            Button {
                printPDF()
            } label: { Label("Печать", systemImage: "printer") }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showPremium) {
            PremiumSheet(month: month).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
        .sheet(isPresented: $showFine) {
            FineSheet(month: month).environmentObject(store)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let d = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.snappy(duration: 0.28)) { month = d }
        Haptics.select()
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                totalCard
                ForEach(rows) { pay in
                    rowCard(pay)
                }
            }
            .padding(listPadding)
            .frame(maxWidth: 820)
        }
        .monthSwipe { shiftMonth($0) }
    }

    /// Отступы списка: на телефоне компактнее.
    private var listPadding: CGFloat {
#if os(iOS)
        14
#else
        20
#endif
    }

    private var totalCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Итого за \(monthTitle.lowercased())")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("К выплате")
                        .font(.headline)
                }
                Spacer(minLength: 8)
                Text("\(Money.grouped(grandTotal)) ₽")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(
                        LinearGradient(colors: [.accentColor, .purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .contentTransition(.numericText())
            }

            Divider()

            HStack {
                Label("Выручка за месяц", systemImage: "banknote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Money.grouped(store.monthRevenue(month))) ₽")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(store.monthRevenue(month) > 0 ? Color.green : Color.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.purple.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
        .animation(.snappy, value: grandTotal)
        .animation(.snappy, value: store.monthRevenue(month))
    }

    private func rowCard(_ pay: EmployeePay) -> some View {
        let isOpen = expanded == pay.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    expanded = isOpen ? nil : pay.id
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pay.employee.role.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(pay.employee.color.gradient,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(pay.employee.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(Money.grouped(pay.total)) ₽")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(pay.total < 0 ? .red : .primary)
                                .contentTransition(.numericText())
                        }
                        Text(summaryLine(pay))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider()
                ForEach(pay.shifts) { s in
                    HStack(spacing: 8) {
                        Text(dayStr(s.date)).font(.callout)
                        Text(s.kind.rawValue)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(s.kind.color.opacity(0.18), in: Capsule())
                        Spacer(minLength: 4)
                        if !s.bonuses.isEmpty {
                            Text("+" + s.bonuses.map { "+\(Int($0.amount))" }.joined(separator: " "))
                                .font(.caption2).foregroundStyle(.green)
                                .lineLimit(1)
                        }
                        Text("\(Money.grouped(s.total)) ₽")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .frame(width: amountWidth, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }

                if !pay.premiums.isEmpty {
                    Divider()
                    ForEach(pay.premiums) { p in
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.note).font(.callout).lineLimit(1)
                                Text(dayStr(p.date))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("+\(Money.grouped(p.amount)) ₽")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.green)
                            rowActions(edit: { editingPremium = p },
                                       delete: { store.deletePremium(p) })
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !pay.fines.isEmpty {
                    Divider()
                    ForEach(pay.fines) { f in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.note).font(.callout).lineLimit(1)
                                Text("удержание")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("−\(Money.grouped(f.amount)) ₽")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.red)
                            rowActions(
                                edit: { if let parent = parentFine(f) { editingFine = parent } },
                                delete: { if let parent = parentFine(f) { deleteFineTarget = parent } }
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .animation(.snappy, value: pay.total)
    }

    /// Краткая строка под именем: смены, база, надбавки, премии, штрафы.
    private func summaryLine(_ pay: EmployeePay) -> String {
        var parts = ["\(pay.workDays) смен",
                     "база \(Money.grouped(pay.baseTotal))",
                     "надбавки \(Money.grouped(pay.bonusTotal))"]
        if pay.premiumTotal > 0 { parts.append("премии +\(Money.grouped(pay.premiumTotal))") }
        if pay.fineTotal > 0 { parts.append("штрафы −\(Money.grouped(pay.fineTotal))") }
        return parts.joined(separator: " · ")
    }

    /// Действия строки начисления. На телефоне — компактное меню (крупная зона нажатия),
    /// на маке — две быстрые кнопки.
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
            Button(action: edit) {
                Image(systemName: "pencil").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Редактировать")
            Button(action: delete) {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Удалить")
        }
        #endif
    }

    private func dayStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM (EEE)"
        return f.string(from: d)
    }

    /// Срез штрафа хранит id вида "fineID|yyyy-MM" — по нему находим исходный штраф.
    private func parentFine(_ slice: FineSlice) -> Fine? {
        guard let raw = slice.id.split(separator: "|").first,
              let uuid = UUID(uuidString: String(raw))
        else { return nil }
        return store.fine(id: uuid)
    }

    // MARK: - Копирование ведомости текстом

    private func copyPayrollText() {
        var text = "Turno — ведомость\n\(monthTitle)\n\n"
        text += "Выручка за месяц: \(Money.grouped(store.monthRevenue(month))) ₽\n"
        text += "К выплате: \(Money.grouped(grandTotal)) ₽\n\n"
        for pay in rows {
            text += "\(pay.employee.name): \(pay.workDays) смен — \(Money.grouped(pay.total)) ₽"
            if pay.premiumTotal > 0 { text += ", премии +\(Money.grouped(pay.premiumTotal))" }
            if pay.fineTotal > 0 { text += ", штрафы −\(Money.grouped(pay.fineTotal))" }
            text += "\n"
        }
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        Haptics.success()
        withAnimation(.snappy) { copyFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.snappy) { copyFlash = false }
        }
    }

    // MARK: - Экспорт CSV

    private func exportCSV() {
        var csv = "Сотрудник;Роль;Смен;База;Надбавки;Премии;Штрафы;Итого\n"
        for pay in rows {
            csv += "\(pay.employee.name);\(pay.employee.role.rawValue);\(pay.workDays);\(Int(pay.baseTotal));\(Int(pay.bonusTotal));\(Int(pay.premiumTotal));\(Int(pay.fineTotal));\(Int(pay.total))\n"
        }
        csv += "ИТОГО;;;;;;\(Int(grandTotal))\n"

        // BOM для корректного открытия в Excel
        let bom = Data([0xEF, 0xBB, 0xBF])
        let data = bom + csv.data(using: .utf8)!
        let name = "Зарплата_\(Keys.day(month)).csv"

        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
        #else
        ShareFile.present(data: data, fileName: name)
        #endif
    }

    // MARK: - PDF

    private func makePDFData() -> Data {
        let pdfData = NSMutableData()
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        ctx.beginPDFPage(nil)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: PlatformColor.black,
        ]
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: PlatformColor.gray,
        ]
        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: 11),
            .foregroundColor: PlatformColor.black,
        ]

        var y = bounds.height - 60
        func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], x: CGFloat) {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }

        draw("Turno — ведомость зарплаты", titleAttrs, x: 40)
        y -= 30
        draw(monthTitle, headAttrs, x: 40)
        y -= 28

        let cols: [CGFloat] = [40, 195, 275, 335, 400, 460, 510, 555]
        let headers = ["Сотрудник", "Роль", "Смен", "База", "Надбавки", "Премии", "Штрафы", "Итого"]
        for (i, h) in headers.enumerated() { draw(h, headAttrs, x: cols[i]) }
        y -= 20
        ctx.setStrokeColor(PlatformColor.lightGray.cgColor)
        ctx.move(to: CGPoint(x: 40, y: y + 4))
        ctx.addLine(to: CGPoint(x: 555, y: y + 4))
        ctx.strokePath()
        y -= 16

        for pay in rows {
            let vals = [pay.employee.name, pay.employee.role.rawValue, "\(pay.workDays)",
                        "\(Int(pay.baseTotal)) ₽", "+\(Int(pay.bonusTotal)) ₽",
                        "+\(Int(pay.premiumTotal)) ₽", "−\(Int(pay.fineTotal)) ₽", "\(Int(pay.total)) ₽"]
            for (i, v) in vals.enumerated() { draw(v, rowAttrs, x: cols[i]) }
            y -= 20
        }

        y -= 8
        ctx.setStrokeColor(PlatformColor.black.cgColor)
        ctx.move(to: CGPoint(x: 40, y: y + 6))
        ctx.addLine(to: CGPoint(x: 555, y: y + 6))
        ctx.strokePath()
        y -= 20
        draw("ИТОГО", headAttrs, x: 440)
        draw("\(Int(grandTotal)) ₽", titleAttrs, x: 495)

        ctx.endPDFPage()
        ctx.closePDF()
        return pdfData as Data
    }

    private func exportPDF() {
        let data = makePDFData()
        let name = "Зарплата_\(Keys.day(month)).pdf"
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.pdf]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
        #else
        ShareFile.present(data: data, fileName: name)
        #endif
    }

    private func printPDF() {
        let data = makePDFData()
        #if os(macOS)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("turno_payroll_\(Keys.day(month)).pdf")
        try? data.write(to: tmp)
        guard let doc = PDFDocument(url: tmp) else { return }
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        view.document = doc
        let op = NSPrintOperation(view: view)
        op.printPanel.options = [.showsCopies, .showsPageRange]
        op.run()
        #else
        // На iOS печать доступна через системную шторку «Поделиться» (AirPrint).
        ShareFile.present(data: data, fileName: "Зарплата_\(Keys.day(month)).pdf")
        #endif
    }
}
