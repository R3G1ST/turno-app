import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

        // MARK: Метаданные синхронизации (на расчёты не влияют)

        /// Время последнего изменения записи: "employee:<id>", "shift:<ключ>", …
        var syncStamps: [String: Date] = [:]
        /// Удаления записей: ключ → когда удалили. Не дают записи «воскреснуть»
        /// при слиянии с другим устройством.
        var syncTombstones: [String: Date] = [:]
        /// Отпечатки записей на момент последнего сохранения. По ним Store
        /// понимает, что именно изменилось, и ставит метку только изменённым.
        var syncSeen: [String: String] = [:]
        /// ID устройства, которое последним сохраняло файл.
        var syncDeviceID: String?
        /// Время последней синхронизации/изменения — для интерфейса.
        var syncUpdatedAt: Date?

        /// Тolerant decoding: каждое поле читается через decodeIfPresent с дефолтом,
        /// поэтому файл любой прошлой/будущей версии читается без ошибки —
        /// недостающие поля просто берут значения по умолчанию.
        init(employees: [Employee] = [], shifts: [String: Shift] = [:],
             revenues: [String: DayRevenue] = [:], thresholds: [BonusThreshold] = [],
             fines: [Fine] = [], premiums: [Premium] = [],
             checkUpdatesOnLaunch: Bool = true, configVersion: Int? = nil,
             syncStamps: [String: Date] = [:], syncTombstones: [String: Date] = [:],
             syncSeen: [String: String] = [:], syncDeviceID: String? = nil,
             syncUpdatedAt: Date? = nil) {
            self.employees = employees
            self.shifts = shifts
            self.revenues = revenues
            self.thresholds = thresholds
            self.fines = fines
            self.premiums = premiums
            self.checkUpdatesOnLaunch = checkUpdatesOnLaunch
            self.configVersion = configVersion
            self.syncStamps = syncStamps
            self.syncTombstones = syncTombstones
            self.syncSeen = syncSeen
            self.syncDeviceID = syncDeviceID
            self.syncUpdatedAt = syncUpdatedAt
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
            syncStamps = try c.decodeIfPresent([String: Date].self, forKey: .syncStamps) ?? [:]
            syncTombstones = try c.decodeIfPresent([String: Date].self, forKey: .syncTombstones) ?? [:]
            syncSeen = try c.decodeIfPresent([String: String].self, forKey: .syncSeen) ?? [:]
            syncDeviceID = try c.decodeIfPresent(String.self, forKey: .syncDeviceID)
            syncUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .syncUpdatedAt)
        }

        /// Совпадает ли содержимое (без служебных метаданных синхронизации).
        func hasSameContent(as other: AppData) -> Bool {
            employees == other.employees
                && shifts == other.shifts
                && revenues == other.revenues
                && thresholds == other.thresholds
                && fines == other.fines
                && premiums == other.premiums
        }
    }

    /// Реальные пороги владельца и базовая ставка.
    static let baseShiftRate: Double = 2300
    static let defaultThresholds: [(revenue: Double, bonus: Double)] = [
        (12000, 300), (16000, 300), (21000, 500),
        (30000, 700), (40000, 700), (50000, 800),
    ]

    @Published var data = AppData()
    /// Вызывается после каждого сохранения на диск — для автосинхронизации.
    /// Не участвует в кодировании и не попадает в файл.
    var onDataSaved: (() -> Void)?
    /// Пока применяем снимок с другого устройства, не помечаем его записи
    /// как «изменённые сейчас» (иначе получится бесконечный обмен).
    private var isApplyingSyncSnapshot = false
    /// Удалось ли загрузить реальные данные (чтобы не перезаписать файл демо-данными).
    private var hasLoadedRealData = false
    /// Файл существует, но не читается и бэкапов нет → не трогаем диск.
    private(set) var loadFailed = false

    static let appName = "Turno"

    /// Постоянный ID этого устройства (не синхронизируется, живёт в UserDefaults).
    static let deviceID: String = {
        let key = "turno.sync.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    /// Локальная папка данных (Application Support) — fallback, когда iCloud недоступен.
    private static var localDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Turno", isDirectory: true)
    }

    /// Папка в iCloud (ubiquity container /Documents/Turno). nil, если iCloud недоступен
    /// (нет подписи с entitlements, либо iCloud выключен). Считается один раз.
    static let iCloudDir: URL? = {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container.appendingPathComponent("Documents/Turno", isDirectory: true)
    }()

    /// Рабочая папка: iCloud, если доступен, иначе локальная.
    static var supportDir: URL { iCloudDir ?? localDir }
    static var localDataFile: URL { localDir.appendingPathComponent("turno.json") }
    static var dataFile: URL { supportDir.appendingPathComponent("turno.json") }
    static var backupsDir: URL { supportDir.appendingPathComponent("Backups", isDirectory: true) }

    private var saveTask: Task<Void, Never>?

    init() {
        migrateToiCloudIfNeeded()
        load()
        // Демо-данные поднимаем только если файла нет вовсе (не когда файл был, но не прочитался).
        if !hasLoadedRealData && !loadFailed {
            seedIfEmpty()
        }
    }

    /// Однократный перенос локальных данных в iCloud (если iCloud доступен, а там ещё пусто).
    private func migrateToiCloudIfNeeded() {
        guard Store.iCloudDir != nil else { return }
        let fm = FileManager.default
        let localFile = Store.localDataFile
        let iCloudFile = Store.dataFile
        guard fm.fileExists(atPath: localFile.path), !fm.fileExists(atPath: iCloudFile.path) else { return }
        try? fm.createDirectory(at: Store.supportDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: localFile, to: iCloudFile)
        // Переносим и резервные копии.
        let localBackups = Store.localDir.appendingPathComponent("Backups")
        let iCloudBackups = Store.backupsDir
        if let files = try? fm.contentsOfDirectory(at: localBackups, includingPropertiesForKeys: nil) {
            try? fm.createDirectory(at: iCloudBackups, withIntermediateDirectories: true)
            for f in files {
                try? fm.copyItem(at: f, to: iCloudBackups.appendingPathComponent(f.lastPathComponent))
            }
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
        refreshSyncStamps()
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? encoder.encode(data) {
            try? raw.write(to: Self.dataFile, options: [.atomic])
        }
        onDataSaved?()
    }

    // MARK: - Метаданные синхронизации

    /// Отпечатки всех записей: неизменённые записи сохраняют свою метку времени,
    /// поэтому при слиянии «побеждает» действительно более свежая версия.
    func currentFingerprints() -> [String: String] {
        var result: [String: String] = [:]
        for e in data.employees {
            result["employee:\(e.id.uuidString)"] = SyncHash.fingerprint(e)
        }
        for (key, s) in data.shifts {
            result["shift:\(key)"] = SyncHash.fingerprint(s)
        }
        for (key, r) in data.revenues {
            result["revenue:\(key)"] = SyncHash.fingerprint(r)
        }
        for t in data.thresholds {
            result["threshold:\(t.id.uuidString)"] = SyncHash.fingerprint(t)
        }
        for f in data.fines {
            result["fine:\(f.id.uuidString)"] = SyncHash.fingerprint(f)
        }
        for p in data.premiums {
            result["premium:\(p.id.uuidString)"] = SyncHash.fingerprint(p)
        }
        return result
    }

    /// Сравнивает текущие отпечатки с прошлым сохранением: изменённым/новым
    /// записям ставит текущее время, для исчезнувших — tombstone.
    func refreshSyncStamps(now: Date = Date()) {
        let current = currentFingerprints()
        data.syncDeviceID = Self.deviceID
        if isApplyingSyncSnapshot {
            data.syncSeen = current
            return
        }
        var changed = false
        for (key, fp) in current where data.syncSeen[key] != fp {
            data.syncStamps[key] = now
            data.syncSeen[key] = fp
            data.syncTombstones.removeValue(forKey: key)
            changed = true
        }
        let removed = Set(data.syncSeen.keys).subtracting(current.keys)
        for key in removed {
            data.syncSeen.removeValue(forKey: key)
            data.syncStamps.removeValue(forKey: key)
            if data.syncTombstones[key] == nil {
                data.syncTombstones[key] = now
            }
            changed = true
        }
        // Старые tombstone-метки не нужны: записи давно нет на обоих устройствах.
        let cutoff = now.addingTimeInterval(-90 * 24 * 3600)
        for (key, date) in data.syncTombstones where date < cutoff {
            data.syncTombstones.removeValue(forKey: key)
        }
        if changed {
            data.syncUpdatedAt = now
        }
    }

    /// Полный снимок для отправки на другое устройство (с актуальными метками).
    func syncSnapshot() -> AppData {
        refreshSyncStamps()
        return data
    }

    /// Применяет снимок, полученный после слияния. Перед заменой делает резервную
    /// копию, а отпечатки берёт из снимка — чтобы не считать чужие записи «своими».
    @discardableResult
    func applySyncSnapshot(_ snapshot: AppData) -> Bool {
        guard !data.hasSameContent(as: snapshot)
                || data.syncStamps != snapshot.syncStamps
                || data.syncTombstones != snapshot.syncTombstones
        else { return false }

        if !data.employees.isEmpty || !data.shifts.isEmpty {
            try? backup()
        }
        var next = snapshot
        next.syncDeviceID = Self.deviceID
        next.configVersion = data.configVersion ?? next.configVersion
        next.checkUpdatesOnLaunch = data.checkUpdatesOnLaunch
        next.syncUpdatedAt = Date()
        isApplyingSyncSnapshot = true
        data = next
        data.syncSeen = currentFingerprints()
        saveNow()                    // refreshSyncStamps увидит флаг и только обновит seen
        isApplyingSyncSnapshot = false
        return true
    }

    /// Слияние с данными другого устройства (без изменения локальных данных).
    func merged(with remote: AppData) -> AppData {
        refreshSyncStamps()
        return SyncMerge.merge(local: data, remote: remote)
    }

    /// Взять данные другого устройства целиком (с его метками времени).
    func adopting(_ remote: AppData) -> AppData {
        var next = remote
        next.syncDeviceID = Self.deviceID
        next.configVersion = data.configVersion ?? remote.configVersion
        next.checkUpdatesOnLaunch = data.checkUpdatesOnLaunch
        next.syncSeen = [:]
        return next
    }

    /// Сделать текущие данные главными: все записи получают метку «сейчас»,
    /// а записи, которых у нас нет, помечаются удалёнными на другом устройстве.
    func authoritative(over remote: AppData) -> AppData {
        refreshSyncStamps()
        let now = Date()
        var next = data
        let localKeys = Set(currentFingerprints().keys)
        let remoteKeys = remote.allRecordKeys()
        for key in remoteKeys.subtracting(localKeys) {
            next.syncTombstones[key] = now
            next.syncStamps.removeValue(forKey: key)
        }
        let fingerprints = currentFingerprints()
        for key in localKeys {
            next.syncStamps[key] = now
            next.syncSeen[key] = fingerprints[key]
            next.syncTombstones.removeValue(forKey: key)
        }
        next.syncUpdatedAt = now
        next.syncDeviceID = Self.deviceID
        next.syncSeen = fingerprints
        return next
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

    // MARK: Экспорт / импорт данных (перенос между маком и телефоном)

    /// JSON-файл со всеми данными — для передачи на другое устройство.
    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(data)
    }

    /// Импорт данных из JSON-файла (перезаписывает текущие; перед этим старые сохраняются в бэкап).
    func importJSON(_ raw: Data) throws {
        // Файл должен быть экспортом Turno — ищем характерные ключи.
        // Иначе любой посторонний JSON (случайно выбранный) декодировался бы
        // как «пустые данные» и затёр текущие.
        guard let obj = try? JSONSerialization.jsonObject(with: raw),
              let dict = obj as? [String: Any],
              dict["employees"] != nil || dict["shifts"] != nil || dict["revenues"] != nil else {
            throw NSError(domain: "Turno", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "в файле нет данных Turno"])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let decoded = try decoder.decode(AppData.self, from: raw)
        // Страховка: текущие данные в бэкап, если они были.
        if !data.employees.isEmpty || !data.shifts.isEmpty {
            try? backup()
        }
        data = decoded
        // Импорт — осознанная замена данных: помечаем всё локальным «сейчас»,
        // чтобы следующая синхронизация не откатила импорт к старым меткам.
        data.syncStamps = [:]
        data.syncTombstones = [:]
        data.syncSeen = [:]
        data.syncUpdatedAt = Date()
        hasLoadedRealData = true
        migrate()
        saveNow()
        showImportMessage(
            "✅ Импортировано: сотрудников — \(decoded.employees.count), смен — \(decoded.shifts.count), дней выручки — \(decoded.revenues.count)",
            error: false)
    }

    // MARK: Импорт по URL (шаринг/«Открыть в Turno»)

    /// Сообщение о результате импорта — показывается алертом из любого места приложения.
    @Published var importMessage: String?
    @Published var importMessageHasError = false

    /// Импорт данных по файлу из Файлов/шаринга. Работает независимо от пикера.
    func importFromFile(url: URL) {
        do {
            // Доступ к файлу из Файлов/шаринга временный — берём сразу.
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let raw = try Data(contentsOf: url)
            guard !raw.isEmpty else {
                throw NSError(domain: "Turno", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "файл пуст"])
            }
            try importJSON(raw)
            lastOpenedFile = url.lastPathComponent
            // Копию из папки Inbox убираем — она больше не нужна.
            if url.path.contains("/Inbox/") {
                try? FileManager.default.removeItem(at: url)
                if samePath(pendingInboxFile, url) { pendingInboxFile = nil }
            } else if isInImportFolder(url) {
                // Файл из папки Turno помечаем обработанным (переименовываем),
                // чтобы баннер не предлагал его при каждом запуске. Сам файл остаётся.
                if url.pathExtension.lowercased() != "imported" {
                    let done = url.deletingPathExtension().appendingPathExtension("imported")
                    try? FileManager.default.removeItem(at: done)
                    try? FileManager.default.moveItem(at: url, to: done)
                }
                if samePath(pendingInboxFile, url) { pendingInboxFile = nil }
            }
        } catch {
            // Не подошёл — помечаем файл, чтобы баннер не предлагал его снова
            // при каждом запуске. Сам файл остаётся на месте.
            let ext = url.pathExtension.lowercased()
            if isInImportFolder(url), ext != "rejected", ext != "imported" {
                let bad = url.deletingPathExtension().appendingPathExtension("rejected")
                try? FileManager.default.removeItem(at: bad)
                try? FileManager.default.moveItem(at: url, to: bad)
            } else if url.path.contains("/Inbox/") {
                rejectedInboxPaths.insert(url.path)
            }
            if samePath(pendingInboxFile, url) { pendingInboxFile = nil }
            showImportMessage(
                "❌ Файл не подошёл.\nНужен JSON-файл, экспортированный из Turno (Настройки → Данные → Экспорт данных).\nПричина: \(error.localizedDescription)",
                error: true)
        }
    }

    // MARK: Страховка: файл из шаринга, если событие открытия «потерялось»

    /// Последний открытый файл (диагностика переноса данных).
    @Published var lastOpenedFile: String?

    /// Файл, найденный в папке Inbox: сюда iOS кладёт открытый в приложение файл,
    /// даже если событие onOpenURL до приложения не дошло. Показываем баннер-предложение.
    @Published var pendingInboxFile: URL?
    /// Файлы Inbox, которые уже не подошли — не предлагаем их повторно.
    private var rejectedInboxPaths = Set<String>()

    /// Папки, в которых ищем файл для импорта. Только iOS:
    /// — Inbox: системная копия документа, открытого в приложение;
    /// — корень Documents: папка Turno, видимая в «Файлах» (UIFileSharingEnabled),
    ///   куда файл кладут вручную («Переместить → На моём iPhone → Turno»).
    /// На маке пусто — сканировать ~/Documents нельзя, там чужие файлы.
    static var importScanFolders: [URL] = {
        #if os(iOS)
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        return [docs.appendingPathComponent("Inbox", isDirectory: true), docs]
        #else
        return []
        #endif
    }()

    /// Проверка папок с файлом. Вызывается при старте, при возврате из фона
    /// и по кнопке в Настройках — это путь, когда события открытия не работают.
    func scanInbox() {
        let fm = FileManager.default
        var candidates: [URL] = []
        for folder in Store.importScanFolders {
            guard let items = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else { continue }
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir { continue }
                if item.lastPathComponent == "turno.json" { continue }   // свои данные не трогаем
                if rejectedInboxPaths.contains(item.path) { continue }
                let ext = item.pathExtension.lowercased()
                if ext == "imported" || ext == "rejected" { continue }   // уже обработан
                if ext == "json" || item.lastPathComponent.lowercased().contains("turno") {
                    candidates.append(item)
                }
            }
        }
        guard let newest = candidates.max(by: { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }) else { return }
        if !samePath(pendingInboxFile, newest) {
            pendingInboxFile = newest
            lastOpenedFile = newest.lastPathComponent
        }
    }

    /// Пользователь нажал на баннер с найденным файлом — импортируем его.
    func acceptPendingInboxFile() {
        guard let url = pendingInboxFile else { return }
        pendingInboxFile = nil
        importFromFile(url: url)
    }

    /// Открытие файла из шаринга/«Открыть в Turno» — основной путь; Inbox — страховка.
    func handleOpenedURL(_ url: URL) {
        guard url.isFileURL else { return }
        lastOpenedFile = url.lastPathComponent
        // Если этот же файл уже показан как найденный в Inbox — баннер снимаем,
        // импорт идёт по URL, дублировать не нужно.
        if samePath(pendingInboxFile, url) { pendingInboxFile = nil }
        // Файл уже обработан и удалён (например, принят из Inbox) — молча выходим.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        importFromFile(url: url)
    }

    #if os(iOS)
    /// Импорт из буфера обмена: в Файлах «Поделиться → Копировать» → здесь вставить.
    /// Работает всегда, даже когда система не отдаёт файл приложению.
    func importFromPasteboard() {
        let pb = UIPasteboard.general
        if let url = pb.urls?.first {
            importFromFile(url: url)
            return
        }
        if let text = pb.string, text.contains("{"), let raw = text.data(using: .utf8) {
            do { try importJSON(raw) }
            catch {
                showImportMessage(
                    "❌ В буфере обмена есть текст, но это не данные Turno.\nПричина: \(error.localizedDescription)",
                    error: true)
            }
            return
        }
        showImportMessage(
            "❌ В буфере обмена нет файла данных.\nСкопируйте его в Файлах: файл → Поделиться → Копировать — и повторите.",
            error: true)
    }
    #endif

    private func showImportMessage(_ text: String, error: Bool) {
        importMessage = text
        importMessageHasError = error
    }

    /// Лежит ли файл в одной из папок импорта (на маке их нет — файлы не трогаем).
    /// Пути сравниваются через resolvingSymlinksInPath: contentsOfDirectory может
    /// вернуть /private/tmp/…, а заданный нами путь — /tmp/… (симлинк).
    private func isInImportFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return Store.importScanFolders.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    /// Равны ли два пути файла (с учётом симлинков).
    private func samePath(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        return a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
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

    /// Суммарная выручка заведения за месяц (сумма всех дней с введённой выручкой).
    func monthRevenue(_ month: Date) -> Double {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return 0 }
        return data.revenues.reduce(0) { sum, item in
            guard let d = Keys.date(fromDayKey: item.key),
                  d >= interval.start, d < interval.end else { return sum }
            return sum + item.value.total
        }
    }

    /// Месяц с последней активностью (смены, выручка, премии, штрафы).
    /// Используется как стартовый месяц в календаре и ведомости, чтобы
    /// приложение открывалось там, где есть данные (не слепо на текущем).
    var lastActiveMonth: Date {
        let cal = Calendar.current
        var candidates: [Date] = []
        for key in data.shifts.keys {
            if let d = Keys.date(fromDayKey: key) { candidates.append(d) }
        }
        for key in data.revenues.keys {
            if let d = Keys.date(fromDayKey: key) { candidates.append(d) }
        }
        for p in data.premiums { candidates.append(p.date) }
        for f in data.fines {
            // startMonth в формате "yyyy-MM" → 1-е число месяца
            let f2 = DateFormatter()
            f2.calendar = Calendar.current
            f2.locale = Locale(identifier: "ru_RU")
            f2.dateFormat = "yyyy-MM"
            if let d = f2.date(from: f.startMonth) { candidates.append(d) }
        }
        guard let last = candidates.max() else { return Date() }
        return cal.date(from: cal.dateComponents([.year, .month], from: last)) ?? Date()
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
