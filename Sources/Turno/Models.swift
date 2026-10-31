import Foundation
import SwiftUI

// MARK: - Роли

enum Role: String, Codable, CaseIterable, Identifiable {
    case hookah = "Кальянщик"
    case waiter = "Официант"
    case admin = "Администратор"
    case cook = "Повар"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hookah: return "smoke"
        case .waiter: return "fork.knife"
        case .admin: return "person.badge.key"
        case .cook: return "flame"
        }
    }

    var color: Color {
        switch self {
        case .hookah: return .teal
        case .waiter: return .orange
        case .admin: return .purple
        case .cook: return .red
        }
    }
}

// MARK: - Вид смены

enum ShiftKind: String, Codable, CaseIterable, Identifiable {
    case work = "Смена"
    case off = "Выходной"

    var id: String { rawValue }

    var isWork: Bool { self == .work }

    var color: Color {
        switch self {
        case .work: return .green
        case .off: return .secondary.opacity(0.35)
        }
    }

    var short: String {
        switch self {
        case .work: return "✓"
        case .off: return "—"
        }
    }
}

// MARK: - Палитра цветов сотрудников

enum Palette {
    static let colors: [(name: String, hex: UInt32)] = [
        ("Синий", 0x3478F6),
        ("Зелёный", 0x28A745),
        ("Оранжевый", 0xF59129),
        ("Красный", 0xE0403A),
        ("Фиолетовый", 0x8E4EC6),
        ("Бирюзовый", 0x24A1A8),
        ("Розовый", 0xE85D9E),
        ("Индиго", 0x5856D6),
        ("Лайм", 0x7CB342),
        ("Коричневый", 0x8D6E4F),
        ("Серый", 0x8E8E93),
        ("Бордовый", 0xA03033),
    ]

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Сотрудник

struct Employee: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var role: Role
    /// Ставка за смену по умолчанию (₽).
    var defaultShiftRate: Double
    var active: Bool
    /// Индивидуальный цвет (hex); nil → берётся цвет роли.
    var colorHex: UInt32?

    init(id: UUID = UUID(), name: String, role: Role, defaultShiftRate: Double, active: Bool = true, colorHex: UInt32? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.defaultShiftRate = defaultShiftRate
        self.active = active
        self.colorHex = colorHex
    }

    /// Цвет сотрудника: собственный или цвет роли.
    var color: Color {
        colorHex.map { Palette.color($0) } ?? role.color
    }
}

// MARK: - Смена (конкретный день у сотрудника)

struct Shift: Codable, Equatable, Hashable {
    var kind: ShiftKind
    /// Индивидуальная ставка за эту смену; nil → берётся ставка сотрудника.
    var rateOverride: Double?

    init(kind: ShiftKind, rateOverride: Double? = nil) {
        self.kind = kind
        self.rateOverride = rateOverride
    }
}

// MARK: - Порог надбавки за выручку заведения

struct BonusThreshold: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Минимальная дневная выручка заведения (₽), при которой начисляется надбавка.
    var revenueFrom: Double
    /// Надбавка каждому, кто отработал смену в этот день (₽).
    var amount: Double
    var enabled: Bool

    init(id: UUID = UUID(), revenueFrom: Double, amount: Double, enabled: Bool = true) {
        self.id = id
        self.revenueFrom = revenueFrom
        self.amount = amount
        self.enabled = enabled
    }
}

// MARK: - Выручка за день

struct DayRevenue: Codable, Equatable, Hashable {
    var hookah: Double
    var bar: Double

    var total: Double { hookah + bar }

    init(hookah: Double = 0, bar: Double = 0) {
        self.hookah = hookah
        self.bar = bar
    }
}

// MARK: - Ключи хранения

enum Keys {
    /// "yyyy-MM-dd"
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// "employeeID|yyyy-MM-dd"
    static func shift(employee: UUID, date: Date) -> String {
        "\(employee.uuidString)|\(day(date))"
    }
}

// MARK: - Шаблоны заполнения

enum FillPattern: String, CaseIterable, Identifiable {
    case twoTwo = "2 через 2"
    case threeOne = "3 через 1"
    case fiveTwo = "5 через 2"
    case sixOne = "6 через 1"
    case allOff = "Все выходные"
    case allFull = "Все смены полные"

    var id: String { rawValue }

    /// Дни работы в цикле; nil — особый случай.
    var workDays: Int? {
        switch self {
        case .twoTwo: return 2
        case .threeOne: return 3
        case .fiveTwo: return 5
        case .sixOne: return 6
        default: return nil
        }
    }

    var restDays: Int? {
        switch self {
        case .twoTwo: return 2
        case .threeOne: return 1
        case .fiveTwo: return 2
        case .sixOne: return 1
        default: return nil
        }
    }
}

// MARK: - Штраф

struct Fine: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var employeeID: UUID
    /// Общая сумма штрафа (₽).
    var totalAmount: Double
    /// Причина (например, «опоздание»).
    var note: String
    /// Месяц начала удержания, "yyyy-MM".
    var startMonth: String
    /// На сколько месяцев разбит (1 = удержать целиком в месяце старта).
    var monthsCount: Int
    var createdAt: Date

    init(id: UUID = UUID(), employeeID: UUID, totalAmount: Double, note: String,
         startMonth: String, monthsCount: Int, createdAt: Date = Date()) {
        self.id = id
        self.employeeID = employeeID
        self.totalAmount = totalAmount
        self.note = note
        self.startMonth = startMonth
        self.monthsCount = max(1, monthsCount)
        self.createdAt = createdAt
    }
}

/// Часть штрафа, удержанная в конкретном месяце.
struct FineSlice: Identifiable {
    let id: String      // "fineID|yyyy-MM" — уникален для каждого месяца
    let note: String
    let amount: Double
}

// MARK: - Премия

struct Premium: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var employeeID: UUID
    /// Сумма премии (₽).
    var amount: Double
    /// День начисления.
    var date: Date
    /// За что (например, «хорошие отзывы гостей»).
    var note: String
    var createdAt: Date

    init(id: UUID = UUID(), employeeID: UUID, amount: Double, date: Date, note: String, createdAt: Date = Date()) {
        self.id = id
        self.employeeID = employeeID
        self.amount = amount
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Результат расчёта зарплаты за смену

struct ShiftPay: Identifiable {
    let id: String          // ключ смены
    let date: Date
    let kind: ShiftKind
    let base: Double        // ставка
    let bonuses: [(threshold: Double, amount: Double)]
    var bonusTotal: Double { bonuses.reduce(0) { $0 + $1.amount } }
    var total: Double { base + bonusTotal }
}

struct EmployeePay: Identifiable {
    let employee: Employee
    let shifts: [ShiftPay]
    let fines: [FineSlice]
    let premiums: [Premium]
    var baseTotal: Double { shifts.reduce(0) { $0 + $1.base } }
    var bonusTotal: Double { shifts.reduce(0) { $0 + $1.bonusTotal } }
    var fineTotal: Double { fines.reduce(0) { $0 + $1.amount } }
    var premiumTotal: Double { premiums.reduce(0) { $0 + $1.amount } }
    var total: Double { baseTotal + bonusTotal + premiumTotal - fineTotal }
    var workDays: Int { shifts.count }
    var id: UUID { employee.id }
}
