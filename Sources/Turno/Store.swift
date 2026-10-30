import Foundation
import SwiftUI

/// Хранилище данных: JSON-файл в ~/Library/Application Support/Turno.
/// Запись атомарная, при старте — автокопия в папку Backups (последние 10).
@MainActor
final class Store: ObservableObject {

    struct AppData: Codable {
        var employees: [Employee] = []
        var shifts: [String: Shift] = [:]          // "employeeID|yyyy-MM-dd" → Shift
        var revenues: [String: DayRevenue] = [:]   // "yyyy-MM-dd" → DayRevenue
        var thresholds: [BonusThreshold] = []
        var checkUpdatesOnLaunch: Bool = true
        var configVersion: Int?                    // версия конфигурации (миграции)
    }

    /// Реальные пороги владельца и базовая ставка.
    static let baseShiftRate: Double = 2300
    static let defaultThresholds: [(revenue: Double, bonus: Double)] = [
        (12000, 300), (16000, 300), (21000, 500),
        (30000, 700), (40000, 700), (50000, 800),
    ]

    @Published var data = AppData()

    static let appName = "Turno"
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Turno", isDirectory: true)
    }
    static var dataFile: URL { supportDir.appendingPathComponent("turno.json") }
    static var backupsDir: URL { supportDir.appendingPathComponent("Backups", isDirectory: true) }

    private var saveTask: Task<Void, Never>?

    init() {
        load()
        seedIfEmpty()
    }

    // MARK: - Загрузка / сохранение

    func load() {
        guard let raw = try? Data(contentsOf: Self.dataFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        if let decoded = try? decoder.decode(AppData.self, from: raw) {
            data = decoded
            migrate()
        }
    }

    /// Первая версия конфигурации: базовая ставка 2300 и пороги владельца.
    private func migrate() {
        guard (data.configVersion ?? 0) < 1 else { return }
        data.configVersion = 1
        for i in data.employees.indices {
            data.employees[i].defaultShiftRate = Self.baseShiftRate
        }
        data.thresholds = Self.defaultThresholds.map {
            BonusThreshold(revenueFrom: $0.revenue, amount: $0.bonus)
        }
        saveNow()
    }

    /// Отложенное (300 мс) атомарное сохранение — не пишем диск на каждый клик.
    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? encoder.encode(data) {
            try? raw.write(to: Self.dataFile, options: [.atomic])
        }
    }

    /// Резервная копия одной кнопкой.
    func backup() throws {
        try? FileManager.default.createDirectory(at: Self.backupsDir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dst = Self.backupsDir.appendingPathComponent("turno_\(f.string(from: Date())).json")
        try FileManager.default.copyItem(at: Self.dataFile, to: dst)
        pruneBackups()
    }

    private func pruneBackups(keep: Int = 10) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.backupsDir, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
        for url in sorted.dropFirst(keep) {
            try? fm.removeItem(at: url)
        }
    }

    private func seedIfEmpty() {
        guard data.employees.isEmpty, data.thresholds.isEmpty else { return }
        data.employees = [
            Employee(name: "Иван Иванов", role: .hookah, defaultShiftRate: Self.baseShiftRate),
            Employee(name: "Пётр Петров", role: .waiter, defaultShiftRate: Self.baseShiftRate),
            Employee(name: "Анна Смирнова", role: .admin, defaultShiftRate: Self.baseShiftRate),
            Employee(name: "Олег Кузнецов", role: .cook, defaultShiftRate: Self.baseShiftRate),
        ]
        data.thresholds = Self.defaultThresholds.map {
            BonusThreshold(revenueFrom: $0.revenue, amount: $0.bonus)
        }
        data.configVersion = 1
    }

    // MARK: - Доступ к сменам

    func shift(employee: UUID, date: Date) -> Shift? {
        data.shifts[Keys.shift(employee: employee, date: date)]
    }

    func setShift(_ shift: Shift?, employee: UUID, date: Date) {
        let key = Keys.shift(employee: employee, date: date)
        if let shift, shift.kind != .off {
            data.shifts[key] = shift
        } else {
            data.shifts[key] = shift          // выходные тоже храним явно — месяц всегда полон
        }
        saveSoon()
    }

    /// Ячейка графика: если смена не задана явно, месяц считается «заполненным выходными».
    func resolvedShift(employee: UUID, date: Date) -> Shift {
        shift(employee: employee, date: date) ?? Shift(kind: .off)
    }

    func revenue(date: Date) -> DayRevenue {
        data.revenues[Keys.day(date)] ?? DayRevenue()
    }

    func setRevenue(_ revenue: DayRevenue, date: Date) {
        if revenue.total == 0 {
            data.revenues.removeValue(forKey: Keys.day(date))
        } else {
            data.revenues[Keys.day(date)] = revenue
        }
        saveSoon()
    }

    // MARK: - Работавшие в день

    func workedEmployees(date: Date) -> [Employee] {
        data.employees.filter { resolvedShift(employee: $0.id, date: date).kind.isWork }
    }

    // MARK: - Расчёт надбавок за день

    /// Активные пороги, превышенные выручкой дня (по убыванию порога).
    func passedThresholds(date: Date) -> [BonusThreshold] {
        let total = revenue(date: date).total
        return data.thresholds
            .filter { $0.enabled && total >= $0.revenueFrom }
            .sorted { $0.revenueFrom > $1.revenueFrom }
    }

    // MARK: - Зарплата за период

    func payroll(from: Date, to: Date) -> [EmployeePay] {
        let cal = Calendar.current
        return data.employees.map { emp in
            var pays: [ShiftPay] = []
            var d = cal.startOfDay(for: from)
            while d <= to {
                let s = resolvedShift(employee: emp.id, date: d)
                if s.kind.isWork {
                    let base = s.rateOverride ?? emp.defaultShiftRate
                    let thrs = passedThresholds(date: d)
                    let bonuses = thrs.map { (threshold: $0.revenueFrom, amount: $0.amount) }
                    pays.append(ShiftPay(id: Keys.shift(employee: emp.id, date: d),
                                         date: d, kind: s.kind, base: base, bonuses: bonuses))
                }
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            return EmployeePay(employee: emp, shifts: pays)
        }
    }

    func payroll(forMonth date: Date) -> [EmployeePay] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return payroll(from: start, to: end)
    }
}
