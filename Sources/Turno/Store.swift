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
        var fines: [Fine] = []
        var premiums: [Premium] = []
        var checkUpdatesOnLaunch: Bool = true
        var configVersion: Int?                    // версия конфигурации (миграции)

        /// Тolerant decoding: каждое поле читается через decodeIfPresent с дефолтом,
        /// поэтому файл любой прошлой/будущей версии читается без ошибки —
        /// недостающие поля просто берут значения по умолчанию.
        init(employees: [Employee] = [], shifts: [String: Shift] = [:],
             revenues: [String: DayRevenue] = [:], thresholds: [BonusThreshold] = [],
             fines: [Fine] = [], premiums: [Premium] = [],
             checkUpdatesOnLaunch: Bool = true, configVersion: Int? = nil) {
            self.employees = employees
            self.shifts = shifts
            self.revenues = revenues
            self.thresholds = thresholds
            self.fines = fines
            self.premiums = premiums
            self.checkUpdatesOnLaunch = checkUpdatesOnLaunch
            self.configVersion = configVersion
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            employees   = try c.decodeIfPresent([Employee].self, forKey: .employees) ?? []
            shifts      = try c.decodeIfPresent([String: Shift].self, forKey: .shifts) ?? [:]
            revenues    = try c.decodeIfPresent([String: DayRevenue].self, forKey: .revenues) ?? [:]
            thresholds  = try c.decodeIfPresent([BonusThreshold].self, forKey: .thresholds) ?? []
            fines       = try c.decodeIfPresent([Fine].self, forKey: .fines) ?? []
            premiums    = try c.decodeIfPresent([Premium].self, forKey: .premiums) ?? []
            checkUpdatesOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .checkUpdatesOnLaunch) ?? true
            configVersion = try c.decodeIfPresent(Int.self, forKey: .configVersion)
        }
    }

    /// Реальные пороги владельца и базовая ставка.
    static let baseShiftRate: Double = 2300
    static let defaultThresholds: [(revenue: Double, bonus: Double)] = [
        (12000, 300), (16000, 300), (21000, 500),
        (30000, 700), (40000, 700), (50000, 800),
    ]

    @Published var data = AppData()
    /// Удалось ли загрузить реальные данные (чтобы не перезаписать файл демо-данными).
    private var hasLoadedRealData = false
    /// Файл существует, но не читается и бэкапов нет → не трогаем диск.
    private(set) var loadFailed = false

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
        // Демо-данные поднимаем только если файла нет вовсе (не когда файл был, но не прочитался).
        if !hasLoadedRealData && !loadFailed {
            seedIfEmpty()
        }
    }

    // MARK: - Загрузка / сохранение

    func load() {
        guard let raw = try? Data(contentsOf: Self.dataFile), !raw.isEmpty else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        if let decoded = try? decoder.decode(AppData.self, from: raw) {
            data = decoded
            hasLoadedRealData = true
            migrate()
            return
        }
        // Файл не читается → пробуем восстановить из самой свежей резервной копии.
        if let recovered = loadFromBackup() {
            data = recovered
            hasLoadedRealData = true
            migrate()       // migrate() сохранит восстановленные данные обратно в основной файл
            return
        }
        // Ни файл, ни бэкапы не читаемы: НЕ поднимаем демо и НЕ перезаписываем диск.
        // Страховка: сохраняем сломанный файл отдельно, чтобы не потерять его.
        preserveCorruptFile()
        loadFailed = true
    }

    /// Копирует нечитаемый основной файл в <имя>.corrupt-<время>, чтобы данные остались для ручного восстановления.
    private func preserveCorruptFile() {
        let fm = FileManager.default
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dst = Self.supportDir.appendingPathComponent("turno_corrupt_\(f.string(from: Date())).json")
        try? fm.copyItem(at: Self.dataFile, to: dst)
    }

    /// Читает самый свежий бэкап, который декодируется. nil — если подходящих нет.
    private func loadFromBackup() -> AppData? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.backupsDir,
                                                      includingPropertiesForKeys: [.creationDateKey])
        else { return nil }
        let sorted = files.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        for url in sorted {
            if let raw = try? Data(contentsOf: url),
               let decoded = try? decoder.decode(AppData.self, from: raw) {
                return decoded
            }
        }
        return nil
    }

    /// Первая версия конфигурации: базовая ставка 2300 и пороги владельца.
    private func migrate() {
        if (data.configVersion ?? 0) < 1 {
            data.configVersion = 1
            for i in data.employees.indices {
                data.employees[i].defaultShiftRate = Self.baseShiftRate
            }
            data.thresholds = Self.defaultThresholds.map {
                BonusThreshold(revenueFrom: $0.revenue, amount: $0.bonus)
            }
        }
        // v2: индивидуальные цвета сотрудникам (по порядку из палитры)
        if (data.configVersion ?? 0) < 2 {
            data.configVersion = 2
            for (i, emp) in data.employees.enumerated() where emp.colorHex == nil {
                data.employees[i].colorHex = Palette.colors[i % Palette.colors.count].hex
            }
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
        let seeds: [(String, Role)] = [
            ("Иван Иванов", .hookah),
            ("Пётр Петров", .waiter),
            ("Анна Смирнова", .admin),
            ("Олег Кузнецов", .cook),
        ]
        data.employees = seeds.enumerated().map { i, s in
            Employee(name: s.0, role: s.1, defaultShiftRate: Self.baseShiftRate,
                     colorHex: Palette.colors[i % Palette.colors.count].hex)
        }
        data.thresholds = Self.defaultThresholds.map {
            BonusThreshold(revenueFrom: $0.revenue, amount: $0.bonus)
        }
        data.configVersion = 2
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
            // Штрафы: срез за каждый месяц, попавший в период
            let slices = fineSlices(employee: emp.id, from: from, to: to)
            // Премии: начисленные внутри периода
            let prems = data.premiums.filter { $0.employeeID == emp.id && $0.date >= from && $0.date <= to }
            return EmployeePay(employee: emp, shifts: pays, fines: slices, premiums: prems)
        }
    }

    // MARK: - Штрафы: срезы по месяцам

    /// Сколько удержать с сотрудника в каждом месяце периода.
    /// Штраф делится равномерно на monthsCount месяцев, начиная со startMonth;
    /// остаток копеек приходится на последний месяц, чтобы сумма сошлась.
    func fineSlices(employee: UUID, from: Date, to: Date) -> [FineSlice] {
        let cal = Calendar.current
        var result: [FineSlice] = []
        for fine in data.fines where fine.employeeID == employee {
            let perMonth = (fine.totalAmount / Double(fine.monthsCount)).rounded()
            guard let start = monthDate(fine.startMonth) else { continue }
            for k in 0..<fine.monthsCount {
                guard let m = cal.date(byAdding: .month, value: k, to: start) else { continue }
                guard m >= cal.date(from: cal.dateComponents([.year, .month], from: from))!,
                      m <= cal.date(from: cal.dateComponents([.year, .month], from: to))!
                else { continue }
                // последний месяц получает остаток
                let amount = (k == fine.monthsCount - 1)
                    ? fine.totalAmount - perMonth * Double(fine.monthsCount - 1)
                    : perMonth
                guard amount != 0 else { continue }
                let key = "\(fine.id.uuidString)|\(monthKey(m))"
                result.append(FineSlice(id: key, note: fine.note, amount: amount))
            }
        }
        return result
    }

    /// "yyyy-MM" → 1-е число месяца.
    func monthDate(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.date(from: key)
    }

    func monthKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    func payroll(forMonth date: Date) -> [EmployeePay] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return payroll(from: start, to: end)
    }

    // MARK: - Управление премиями

    func premium(id: UUID) -> Premium? {
        data.premiums.first { $0.id == id }
    }

    func upsertPremium(_ p: Premium) {
        if let i = data.premiums.firstIndex(where: { $0.id == p.id }) {
            data.premiums[i] = p
        } else {
            data.premiums.append(p)
        }
        saveNow()
    }

    func deletePremium(_ p: Premium) {
        data.premiums.removeAll { $0.id == p.id }
        saveNow()
    }

    // MARK: - Управление штрафами

    func fine(id: UUID) -> Fine? {
        data.fines.first { $0.id == id }
    }

    func upsertFine(_ f: Fine) {
        if let i = data.fines.firstIndex(where: { $0.id == f.id }) {
            data.fines[i] = f
        } else {
            data.fines.append(f)
        }
        saveNow()
    }

    /// Удаляет штраф целиком (по всем месяцам разбивки).
    func deleteFine(_ f: Fine) {
        data.fines.removeAll { $0.id == f.id }
        saveNow()
    }

    /// Все премии, отсортированные по дате (для окна управления).
    func allPremiums() -> [Premium] {
        data.premiums.sorted { $0.date < $1.date }
    }

    /// Все штрафы, отсортированные по месяцу старта (для окна управления).
    func allFines() -> [Fine] {
        data.fines.sorted { $0.startMonth < $1.startMonth }
    }

    func employeeName(_ id: UUID) -> String {
        data.employees.first { $0.id == id }?.name ?? "Удалённый сотрудник"
    }
}
