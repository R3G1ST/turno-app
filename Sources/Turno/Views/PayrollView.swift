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
        .sheet(isPresented: $showManager) {
            AdjustmentsManager(month: month).environmentObject(store)
        }
        .sheet(item: $editingPremium) { p in
            PremiumSheet(month: month, existing: p).environmentObject(store)
        }
        .sheet(item: $editingFine) { f in
            FineSheet(month: month, existing: f).environmentObject(store)
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

    /// Компактная шапка под телефон: месяц отдельной строкой, кнопки — в горизонтальной прокрутке.
    private var compactHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                Text(monthTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    Button { showPremium = true } label: {
                        Label("Премия", systemImage: "star").font(.subheadline)
                    }
                    Button { showFine = true } label: {
                        Label("Штраф", systemImage: "exclamationmark.octagon").font(.subheadline)
                    }
                    Button { showManager = true } label: {
                        Label("Все начисления", systemImage: "list.bullet.rectangle").font(.subheadline)
                    }
                    Button { exportCSV() } label: {
                        Label("CSV", systemImage: "tablecells").font(.subheadline)
                    }
                    Button { exportPDF() } label: {
                        Label("PDF", systemImage: "doc.richtext").font(.subheadline)
                    }
                    Button { printPDF() } label: {
                        Label("Печать", systemImage: "printer").font(.subheadline)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showPremium) {
            PremiumSheet(month: month).environmentObject(store)
        }
        .sheet(isPresented: $showFine) {
            FineSheet(month: month).environmentObject(store)
        }
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
        }
        .sheet(isPresented: $showFine) {
            FineSheet(month: month).environmentObject(store)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: month) { month = d }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                totalCard
                ForEach(rows) { pay in
                    rowCard(pay)
                }
            }
            .padding(20)
            .frame(maxWidth: 820)
        }
    }

    private var totalCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Итого за \(monthTitle.lowercased())")
                    .font(.caption).foregroundStyle(.secondary)
                Text("К выплате")
                    .font(.headline)
            }
            Spacer()
            Text("\(Int(grandTotal)) ₽")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .purple], startPoint: .leading, endPoint: .trailing)
                )
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func rowCard(_ pay: EmployeePay) -> some View {
        let isOpen = expanded == pay.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded = isOpen ? nil : pay.id }
            } label: {
                HStack {
                    Image(systemName: pay.employee.role.icon)
                        .foregroundStyle(pay.employee.color)
                    VStack(alignment: .leading) {
                        Text(pay.employee.name).fontWeight(.medium)
                        Text("\(pay.workDays) смен · база \(Int(pay.baseTotal)) · надбавки \(Int(pay.bonusTotal))"
                             + (pay.premiumTotal > 0 ? " · премии +\(Int(pay.premiumTotal))" : "")
                             + (pay.fineTotal > 0 ? " · штрафы −\(Int(pay.fineTotal))" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(pay.total)) ₽")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(pay.total < 0 ? .red : .primary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider()
                ForEach(pay.shifts) { s in
                    HStack {
                        Text(dayStr(s.date)).font(.callout)
                        Text(s.kind.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(s.kind.color.opacity(0.2), in: Capsule())
                        Spacer()
                        if !s.bonuses.isEmpty {
                            Text("+" + s.bonuses.map { "+\(Int($0.amount))" }.joined(separator: " "))
                                .font(.caption).foregroundStyle(.green)
                        }
                        Text("\(Int(s.total)) ₽")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .frame(width: amountWidth, alignment: .trailing)
                    }
                    .font(.callout)
                }

                if !pay.premiums.isEmpty {
                    Divider()
                    ForEach(pay.premiums) { p in
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(p.note).font(.callout).lineLimit(1)
                            Spacer()
                            Text(dayStr(p.date)).font(.caption).foregroundStyle(.secondary)
                            Text("+\(Int(p.amount)) ₽")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.green)
                                .frame(width: amountWidth, alignment: .trailing)
                            Button { editingPremium = p } label: {
                                Image(systemName: "pencil").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Редактировать премию")
                            Button { store.deletePremium(p) } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Удалить премию")
                        }
                    }
                }

                if !pay.fines.isEmpty {
                    Divider()
                    ForEach(pay.fines) { f in
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(f.note).font(.callout).lineLimit(1)
                            Spacer()
                            Text("удержание").font(.caption).foregroundStyle(.secondary)
                            Text("−\(Int(f.amount)) ₽")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.red)
                                .frame(width: amountWidth, alignment: .trailing)
                            Button { if let parent = parentFine(f) { editingFine = parent } } label: {
                                Image(systemName: "pencil").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Редактировать штраф (весь, по всем месяцам)")
                            Button { if let parent = parentFine(f) { deleteFineTarget = parent } } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Удалить штраф (весь, по всем месяцам)")
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
