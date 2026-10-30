import SwiftUI
import AppKit
import PDFKit

// MARK: - Зарплата за месяц + экспорт PDF/CSV

struct PayrollView: View {
    @EnvironmentObject var store: Store
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var expanded: UUID?

    private var cal: Calendar { Calendar.current }
    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: month).capitalized
    }
    private var rows: [EmployeePay] { store.payroll(forMonth: month) }
    private var grandTotal: Double { rows.reduce(0) { $0 + $1.total } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
            Text(monthTitle).font(.title3.weight(.semibold)).frame(width: 180)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            Spacer()
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
                        .foregroundStyle(pay.employee.role.color)
                    VStack(alignment: .leading) {
                        Text(pay.employee.name).fontWeight(.medium)
                        Text("\(pay.workDays) смен · база \(Int(pay.baseTotal)) · надбавки \(Int(pay.bonusTotal))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(pay.total)) ₽")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
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
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.callout)
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

    // MARK: - Экспорт CSV

    private func exportCSV() {
        var csv = "Сотрудник;Роль;Смен;База;Надбавки;Итого\n"
        for pay in rows {
            csv += "\(pay.employee.name);\(pay.employee.role.rawValue);\(pay.workDays);\(Int(pay.baseTotal));\(Int(pay.bonusTotal));\(Int(pay.total))\n"
        }
        csv += "ИТОГО;;;;;\(Int(grandTotal))\n"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Зарплата_\(Keys.day(month)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                // BOM для корректного открытия в Excel
                let bom = Data([0xEF, 0xBB, 0xBF])
                try? (bom + csv.data(using: .utf8)!).write(to: url)
            }
        }
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
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.gray,
        ]
        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black,
        ]

        var y = bounds.height - 60
        func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], x: CGFloat) {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }

        draw("Turno — ведомость зарплаты", titleAttrs, x: 40)
        y -= 30
        draw(monthTitle, headAttrs, x: 40)
        y -= 28

        let cols: [CGFloat] = [40, 220, 300, 370, 440, 505]
        let headers = ["Сотрудник", "Роль", "Смен", "База", "Надбавки", "Итого"]
        for (i, h) in headers.enumerated() { draw(h, headAttrs, x: cols[i]) }
        y -= 20
        ctx.setStrokeColor(NSColor.lightGray.cgColor)
        ctx.move(to: CGPoint(x: 40, y: y + 4))
        ctx.addLine(to: CGPoint(x: 555, y: y + 4))
        ctx.strokePath()
        y -= 16

        for pay in rows {
            let vals = [pay.employee.name, pay.employee.role.rawValue, "\(pay.workDays)",
                        "\(Int(pay.baseTotal)) ₽", "+\(Int(pay.bonusTotal)) ₽", "\(Int(pay.total)) ₽"]
            for (i, v) in vals.enumerated() { draw(v, rowAttrs, x: cols[i]) }
            y -= 20
        }

        y -= 8
        ctx.setStrokeColor(NSColor.black.cgColor)
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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Зарплата_\(Keys.day(month)).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? makePDFData().write(to: url)
            }
        }
    }

    private func printPDF() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("turno_payroll_\(Keys.day(month)).pdf")
        try? makePDFData().write(to: tmp)
        guard let doc = PDFDocument(url: tmp) else { return }
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        view.document = doc
        let op = NSPrintOperation(view: view)
        op.printPanel.options = [.showsCopies, .showsPageRange]
        op.run()
    }
}
