import Foundation
import CryptoKit
import Network
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Отпечатки записей

/// Стабильный отпечаток записи: одинаковые данные → одинаковый хеш
/// на Mac и iPhone. Нужен, чтобы отличать реальные изменения от простого
/// пересохранения файла.
enum SyncHash {
    static func fingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        guard let raw = try? encoder.encode(value) else { return "0" }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in raw {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Ключи записей

extension Store.AppData {
    /// Все ключи записей, которые участвуют в синхронизации.
    func allRecordKeys() -> Set<String> {
        var keys = Set<String>()
        for e in employees { keys.insert("employee:\(e.id.uuidString)") }
        for key in shifts.keys { keys.insert("shift:\(key)") }
        for key in revenues.keys { keys.insert("revenue:\(key)") }
        for t in thresholds { keys.insert("threshold:\(t.id.uuidString)") }
        for f in fines { keys.insert("fine:\(f.id.uuidString)") }
        for p in premiums { keys.insert("premium:\(p.id.uuidString)") }
        return keys
    }
}

// MARK: - Слияние данных

enum SyncMerge {

    /// Слияние по принципу «последняя правка побеждает». Функция симметрична:
    /// merge(A, B) и merge(B, A) дают одинаковый результат — это важно, чтобы
    /// Mac и iPhone пришли к одному состоянию.
    static func merge(local: Store.AppData, remote: Store.AppData) -> Store.AppData {
        var out = local
        var stamps: [String: Date] = [:]
        var tombstones: [String: Date] = [:]

        let localEmp = Dictionary(uniqueKeysWithValues: local.employees.map { ("employee:\($0.id.uuidString)", $0) })
        let remoteEmp = Dictionary(uniqueKeysWithValues: remote.employees.map { ("employee:\($0.id.uuidString)", $0) })
        let mergedEmp = mergeRecords(local: localEmp, remote: remoteEmp,
                                     localStamps: local.syncStamps, remoteStamps: remote.syncStamps,
                                     localTomb: local.syncTombstones, remoteTomb: remote.syncTombstones,
                                     stamps: &stamps, tombstones: &tombstones)
        out.employees = ordered(mergedEmp,
                                first: orderSource(local: local, remote: remote) == .local
                                    ? local.employees.map { "employee:\($0.id.uuidString)" }
                                    : remote.employees.map { "employee:\($0.id.uuidString)" },
                                second: orderSource(local: local, remote: remote) == .local
                                    ? remote.employees.map { "employee:\($0.id.uuidString)" }
                                    : local.employees.map { "employee:\($0.id.uuidString)" })

        let mergedShifts = mergeRecords(local: prefixed(local.shifts, "shift:"),
                                        remote: prefixed(remote.shifts, "shift:"),
                                        localStamps: local.syncStamps, remoteStamps: remote.syncStamps,
                                        localTomb: local.syncTombstones, remoteTomb: remote.syncTombstones,
                                        stamps: &stamps, tombstones: &tombstones)
        out.shifts = unprefixed(mergedShifts, "shift:")

        let mergedRevenues = mergeRecords(local: prefixed(local.revenues, "revenue:"),
                                          remote: prefixed(remote.revenues, "revenue:"),
                                          localStamps: local.syncStamps, remoteStamps: remote.syncStamps,
                                          localTomb: local.syncTombstones, remoteTomb: remote.syncTombstones,
                                          stamps: &stamps, tombstones: &tombstones)
        out.revenues = unprefixed(mergedRevenues, "revenue:")

        let localThr = Dictionary(uniqueKeysWithValues: local.thresholds.map { ("threshold:\($0.id.uuidString)", $0) })
        let remoteThr = Dictionary(uniqueKeysWithValues: remote.thresholds.map { ("threshold:\($0.id.uuidString)", $0) })
        let mergedThr = mergeRecords(local: localThr, remote: remoteThr,
                                     localStamps: local.syncStamps, remoteStamps: remote.syncStamps,
                                     localTomb: local.syncTombstones, remoteTomb: remote.syncTombstones,
                                     stamps: &stamps, tombstones: &tombstones)
        out.thresholds = mergedThr.values.sorted {
            $0.revenueFrom == $1.revenueFrom
                ? $0.id.uuidString < $1.id.uuidString
                : $0.revenueFrom < $1.revenueFrom
        }

        let localFines = Dictionary(uniqueKeysWithValues: local.fines.map { ("fine:\($0.id.uuidString)", $0) })
        let remoteFines = Dictionary(uniqueKeysWithValues: remote.fines.map { ("fine:\($0.id.uuidString)", $0) })
        let mergedFines = mergeRecords(local: localFines, remote: remoteFines,
                                       localStamps: local.syncStamps, remoteStamps: remote.syncStamps,
                                       localTomb: local.syncTombstones, remoteTomb: remote.syncTombstones,
                                       stamps: &stamps, tombstones: &tombstones)
        out.fines = mergedFines.values.sorted {
            $0.startMonth == $1.startMonth
                ? $0.id.uuidString < $1.id.uuidString
                : $0.startMonth < $1.startMonth
        }

        let localPrems = Dictionary(uniqueKeysWithValues: local.premiums.map { ("premium:\($0.id.uuidString)", $0) })
        let remotePrems = Dictionary(uniqueKeysWithValues: remote.premiums.map { ("premium:\($0.id.uuidString)", $0) })
        let mergedPrems = mergeRecords(local: localPrems, remote: remotePrems,
                                       localStamps: local.syncStamps, remoteStamps: remote.syncStamps,
                                       localTomb: local.syncTombstones, remoteTomb: remote.syncTombstones,
                                       stamps: &stamps, tombstones: &tombstones)
        out.premiums = mergedPrems.values.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }

        // Старые tombstone-метки не храним дольше 90 дней.
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        out.syncTombstones = tombstones.filter { $0.value >= cutoff }
        out.syncStamps = stamps
        out.syncSeen = [:]
        out.syncUpdatedAt = max(local.syncUpdatedAt ?? .distantPast,
                                remote.syncUpdatedAt ?? .distantPast)
        return out
    }

    // MARK: Внутреннее

    private enum OrderSource { case local, remote }

    /// Какая сторона задаёт порядок списков. Выбор симметричен относительно
    /// двух снимков, поэтому оба устройства получат одинаковый порядок.
    private static func orderSource(local: Store.AppData, remote: Store.AppData) -> OrderSource {
        let lt = local.syncUpdatedAt ?? .distantPast
        let rt = remote.syncUpdatedAt ?? .distantPast
        if lt != rt { return lt > rt ? .local : .remote }
        let ld = local.syncDeviceID ?? ""
        let rd = remote.syncDeviceID ?? ""
        return ld >= rd ? .local : .remote
    }

    private static func ordered<T>(_ map: [String: T], first: [String], second: [String]) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        for key in first + second where !seen.contains(key) {
            seen.insert(key)
            if let value = map[key] { result.append(value) }
        }
        return result
    }

    private static func prefixed<T>(_ dict: [String: T], _ prefix: String) -> [String: T] {
        Dictionary(uniqueKeysWithValues: dict.map { (prefix + $0.key, $0.value) })
    }

    private static func unprefixed<T>(_ dict: [String: T], _ prefix: String) -> [String: T] {
        Dictionary(uniqueKeysWithValues: dict.map {
            (String($0.key.dropFirst(prefix.count)), $0.value)
        })
    }

    private static func mergeRecords<T: Equatable & Encodable>(
        local: [String: T], remote: [String: T],
        localStamps: [String: Date], remoteStamps: [String: Date],
        localTomb: [String: Date], remoteTomb: [String: Date],
        stamps: inout [String: Date], tombstones: inout [String: Date]
    ) -> [String: T] {
        var result: [String: T] = [:]
        let keys = Set(local.keys)
            .union(remote.keys)
            .union(localStamps.keys)
            .union(remoteStamps.keys)

        for key in keys {
            let l = local[key]
            let r = remote[key]
            let ls = localStamps[key]
            let rs = remoteStamps[key]
            let lt = localTomb[key]
            let rt = remoteTomb[key]
            let tomb = [lt, rt].compactMap { $0 }.max()

            switch (l, r) {
            case let (lv?, rv?):
                let lTime = ls ?? .distantPast
                let rTime = rs ?? .distantPast
                let winner: T
                let stamp: Date
                if lTime > rTime {
                    winner = lv; stamp = lTime
                } else if rTime > lTime {
                    winner = rv; stamp = rTime
                } else {
                    // Одинаковое время — детерминированный выбор по отпечатку.
                    winner = SyncHash.fingerprint(lv) >= SyncHash.fingerprint(rv) ? lv : rv
                    stamp = lTime
                }
                result[key] = winner
                stamps[key] = stamp

            case let (lv?, nil):
                // Если на другой стороне запись удалена позже последней правки — удаляем.
                if let deletedAt = rt, deletedAt >= (ls ?? .distantPast) {
                    // остаётся только tombstone
                } else {
                    result[key] = lv
                    stamps[key] = ls ?? .distantPast
                }

            case let (nil, rv?):
                if let deletedAt = lt, deletedAt >= (rs ?? .distantPast) {
                    // удалено здесь
                } else {
                    result[key] = rv
                    stamps[key] = rs ?? .distantPast
                }

            case (nil, nil):
                break
            }

            if let tomb { tombstones[key] = tomb }
        }
        return result
    }
}

// MARK: - Кодирование снимка

enum SyncCodec {
    static func encode(_ data: Store.AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(data)
    }

    static func decode(_ raw: Data) throws -> Store.AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(Store.AppData.self, from: raw)
    }
}

// MARK: - Ошибки

enum SyncError: LocalizedError {
    case notConfigured
    case badCode
    case unauthorized
    case notFound
    case conflict
    case http(Int)
    case badData
    case timeout
    case network(String)
    case serverUnavailable
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Укажите репозиторий и токен GitHub"
        case .badCode:
            return "Неверный код подключения"
        case .unauthorized:
            return "GitHub не принял токен. Нужен fine-grained token с правом Contents: Read and write на репозиторий синхронизации."
        case .notFound:
            return "Файл turno.json не найден в репозитории. Нажмите «Загрузить на GitHub», чтобы создать его."
        case .conflict:
            return "Файл на GitHub успел измениться. Попробуйте синхронизацию ещё раз."
        case .http(let code):
            return "GitHub вернул ошибку \(code)"
        case .badData:
            return "Данные не распознаны"
        case .timeout:
            return "Истекло время ожидания. Проверьте, что Mac рядом и приём включён."
        case .network(let text):
            return text
        case .serverUnavailable:
            return "Приём на Mac не запущен"
        case .rateLimited:
            return "GitHub временно ограничил частоту запросов. Синхронизация продолжится автоматически через несколько минут."
        }
    }
}

// MARK: - Ответ GitHub с учётом ETag

struct GitHubRemote {
    let data: Store.AppData
    let sha: String
    let etag: String?
}

enum GitHubLoad {
    case notModified(etag: String?)
    case remote(GitHubRemote)
}

// MARK: - GitHub Contents API

struct GitHubClient {
    let repo: String
    let token: String
    var branch = "main"
    var path = "turno.json"

    private var contentsURL: URL? {
        URL(string: "https://api.github.com/repos/\(repo)/contents/\(path)?ref=\(branch)")
    }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil,
                         ifNoneMatch: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        // Ответ должен быть свежим: кэш URLSession не участвует в синхронизации.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Turno/1.0.19", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let ifNoneMatch {
            req.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    /// 403 от GitHub — это либо мало прав у токена, либо исчерпан лимит запросов.
    private func throwIfRateLimited(_ http: HTTPURLResponse) throws {
        if http.statusCode == 429 {
            throw SyncError.rateLimited
        }
        if http.statusCode == 403,
           http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            throw SyncError.rateLimited
        }
    }

    /// Загружает файл. Если передан etag и файл не менялся, GitHub отвечает
    /// 304 — такой запрос не расходует лимит, поэтому опрос раз в секунду
    /// безопасен для двух устройств.
    func load(ifNoneMatch: String? = nil) async throws -> GitHubLoad {
        guard !repo.isEmpty, !token.isEmpty else { throw SyncError.notConfigured }
        guard let url = contentsURL else { throw SyncError.notConfigured }
        let (raw, response) = try await URLSession.shared.data(
            for: request(url, ifNoneMatch: ifNoneMatch))
        guard let http = response as? HTTPURLResponse else { throw SyncError.badData }
        try throwIfRateLimited(http)

        let etag = http.value(forHTTPHeaderField: "ETag")
        switch http.statusCode {
        case 304:
            return .notModified(etag: etag)
        case 200:
            break
        case 401:
            throw SyncError.unauthorized
        case 404:
            throw SyncError.notFound
        default:
            throw SyncError.http(http.statusCode)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let content = obj["content"] as? String,
              let sha = obj["sha"] as? String,
              let decoded = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: ""))
        else { throw SyncError.badData }
        return .remote(GitHubRemote(data: try SyncCodec.decode(decoded), sha: sha, etag: etag))
    }

    /// Удобная форма для ручных действий: всегда читает файл целиком.
    func load() async throws -> (data: Store.AppData, sha: String, etag: String?) {
        switch try await load(ifNoneMatch: nil) {
        case .remote(let remote):
            return (remote.data, remote.sha, remote.etag)
        case .notModified:
            throw SyncError.badData
        }
    }

    func save(_ data: Store.AppData, sha: String?) async throws -> String {
        guard !repo.isEmpty, !token.isEmpty else { throw SyncError.notConfigured }
        guard let base = contentsURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { throw SyncError.notConfigured }
        components.query = nil
        guard let url = components.url else { throw SyncError.notConfigured }

        let raw = try SyncCodec.encode(data)
        var body: [String: Any] = [
            "message": "Turno: синхронизация (\(DeviceInfo.name))",
            "content": raw.base64EncodedString(),
            "branch": branch,
        ]
        if let sha { body["sha"] = sha }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (answer, response) = try await URLSession.shared.data(
            for: request(url, method: "PUT", body: bodyData))
        guard let http = response as? HTTPURLResponse else { throw SyncError.badData }
        try throwIfRateLimited(http)
        switch http.statusCode {
        case 200, 201:
            let obj = try? JSONSerialization.jsonObject(with: answer) as? [String: Any]
            let content = obj?["content"] as? [String: Any]
            return content?["sha"] as? String ?? ""
        case 401:
            throw SyncError.unauthorized
        case 409, 422:
            throw SyncError.conflict
        default:
            throw SyncError.http(http.statusCode)
        }
    }
}

enum DeviceInfo {
    static var name: String {
        #if os(macOS)
        return ProcessInfo.processInfo.hostName
        #else
        return UIDevice.current.name
        #endif
    }
}

// MARK: - Шифрование Wi-Fi обмена

enum SyncCrypto {
    static func key(code: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data("turno-wifi:\(code)".utf8))
        return SymmetricKey(data: Data(digest))
    }

    static func seal(_ data: Data, code: String) throws -> Data {
        let box = try AES.GCM.seal(data, using: key(code: code))
        guard let combined = box.combined else { throw SyncError.badData }
        return combined
    }

    static func open(_ data: Data, code: String) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key(code: code))
        } catch {
            throw SyncError.badCode
        }
    }
}

// MARK: - Кадры TCP (длина + данные)

enum SyncFrame {
    static func wrap(_ payload: Data) -> Data {
        var out = Data()
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    /// Возвращает payload, если в буфере уже есть целый кадр.
    static func extract(from buffer: Data) -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).withUnsafeBytes { raw in
            UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self))
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        return buffer.subdata(in: 4..<total)
    }
}

// MARK: - Wi-Fi: Mac-сервер

@MainActor
final class WiFiSyncServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var status = "Выключен"
    @Published private(set) var lastClientAt: Date?

    /// Код, которым шифруется обмен. Меняется в настройках.
    var code: String = ""
    /// Обработчик: получает снимок iPhone, возвращает снимок после слияния.
    var handleSnapshot: ((Store.AppData) -> Store.AppData)?

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    func start() {
        guard !isRunning else { return }
        guard code.count >= 4 else {
            status = "Сначала задайте код подключения"
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: "Turno — \(DeviceInfo.name)", type: "_turno._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handleState(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
            isRunning = true
            status = "Ждём iPhone…"
        } catch {
            status = "Не удалось включить приём: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        isRunning = false
        status = "Выключен"
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = "Ждём iPhone…"
        case .failed(let error):
            status = "Приём остановлен: \(error.localizedDescription)"
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.drop(id) }
            } else if case .cancelled = state {
                Task { @MainActor in self?.drop(id) }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection, id: id, buffer: Data())
    }

    private func receive(on connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            var accumulated = buffer
            if let data, !data.isEmpty { accumulated.append(data) }
            if let payload = SyncFrame.extract(from: accumulated) {
                Task { @MainActor in self?.process(payload, id: id) }
                return
            }
            if isComplete || error != nil {
                Task { @MainActor in self?.drop(id) }
                return
            }
            Task { @MainActor in
                guard let self, let connection = self.connections[id] else { return }
                self.receive(on: connection, id: id, buffer: accumulated)
            }
        }
    }

    private func process(_ payload: Data, id: UUID) {
        guard let connection = connections[id], let handler = handleSnapshot else {
            drop(id)
            return
        }
        do {
            let raw = try SyncCrypto.open(payload, code: code)
            let remote = try SyncCodec.decode(raw)
            lastClientAt = Date()
            let merged = handler(remote)
            let answer = try SyncCrypto.seal(try SyncCodec.encode(merged), code: code)
            status = "Синхронизировано с iPhone"
            send(answer, on: connection, id: id)
        } catch {
            status = "Не удалось принять данные: \(error.localizedDescription)"
            drop(id)
        }
    }

    private func send(_ payload: Data, on connection: NWConnection, id: UUID) {
        connection.send(content: SyncFrame.wrap(payload), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.drop(id) }
        })
    }

    private func drop(_ id: UUID) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
    }
}

// MARK: - Wi-Fi: поиск Mac и клиент

struct WiFiPeer: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint

    static func == (lhs: WiFiPeer, rhs: WiFiPeer) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class WiFiBrowser: ObservableObject {
    @Published private(set) var peers: [WiFiPeer] = []
    @Published private(set) var status = "Поиск не запущен"

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_turno._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.status = "Ищем Mac в этой сети…"
                case .failed(let error):
                    self?.status = "Поиск не работает: \(error.localizedDescription)"
                case .cancelled:
                    self?.status = "Поиск остановлен"
                default:
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.peers = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return WiFiPeer(id: String(describing: result.endpoint),
                                    name: name.replacingOccurrences(of: "\u{00A0}", with: " "),
                                    endpoint: result.endpoint)
                }
                .sorted { $0.name < $1.name }
                if self.peers.isEmpty {
                    self.status = "Mac пока не найден. Проверьте, что оба устройства в одной сети Wi-Fi и на Mac включён приём."
                } else {
                    self.status = "Найдено: \(self.peers.count). Выберите Mac."
                }
            }
        }
        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
        status = "Ищем Mac в этой сети…"
    }

    func stop() {
        browser?.cancel()
        browser = nil
        peers = []
        status = "Поиск остановлен"
    }
}

/// Одноразовая обёртка над continuation: защищает от двойного возобновления.
private final class OneShot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

enum WiFiSyncClient {
    /// Подключается к Mac, отправляет зашифрованный снимок и ждёт ответ.
    static func exchange(endpoint: NWEndpoint, code: String, payload: Data) async throws -> Data {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let request = try SyncCrypto.seal(payload, code: code)

        return try await withCheckedThrowingContinuation { continuation in
            let once = OneShot<Data>(continuation)

            _ = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                once.resume(.failure(SyncError.timeout))
                connection.cancel()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: SyncFrame.wrap(request), completion: .contentProcessed { error in
                        if let error {
                            once.resume(.failure(SyncError.network(error.localizedDescription)))
                            connection.cancel()
                            return
                        }
                        receive(on: connection, buffer: Data(), once: once)
                    })
                case .failed(let error):
                    once.resume(.failure(SyncError.network(error.localizedDescription)))
                case .cancelled:
                    once.resume(.failure(SyncError.serverUnavailable))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func receive(on connection: NWConnection, buffer: Data, once: OneShot<Data>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
            var accumulated = buffer
            if let data, !data.isEmpty { accumulated.append(data) }

            if let frame = SyncFrame.extract(from: accumulated) {
                once.resume(.success(frame))
                connection.cancel()
                return
            }
            if let error {
                once.resume(.failure(SyncError.network(error.localizedDescription)))
                connection.cancel()
                return
            }
            if isComplete {
                once.resume(.failure(SyncError.badCode))
                connection.cancel()
                return
            }
            receive(on: connection, buffer: accumulated, once: once)
        }
    }
}

// MARK: - Менеджер синхронизации

@MainActor
final class SyncManager: ObservableObject {

    enum Direction {
        case merge, download, upload
    }

    private enum DefaultsKey {
        static let repo = "turno.sync.github.repo"
        static let token = "turno.sync.github.token"
        static let autoGitHub = "turno.sync.github.auto"
        static let initialized = "turno.sync.github.initialized"
        // Ключи Wi-Fi оставлены на будущее: сам способ временно отключён.
        static let wifiEnabled = "turno.sync.wifi.enabled"
        static let wifiCode = "turno.sync.wifi.code"
        static let wifiAuto = "turno.sync.wifi.auto"
        static let wifiInitialized = "turno.sync.wifi.initialized"
    }

    @Published var githubRepo: String {
        didSet {
            UserDefaults.standard.set(githubRepo, forKey: DefaultsKey.repo)
            credentialsChanged()
        }
    }
    @Published var githubToken: String {
        didSet {
            UserDefaults.standard.set(githubToken, forKey: DefaultsKey.token)
            credentialsChanged()
        }
    }
    @Published var autoGitHub: Bool {
        didSet {
            UserDefaults.standard.set(autoGitHub, forKey: DefaultsKey.autoGitHub)
            if autoGitHub {
                ensureRealtime()
            } else {
                stopRealtime()
            }
        }
    }
    /// Wi-Fi-синхронизация временно отключена: значение всегда false.
    @Published var wifiEnabled: Bool {
        didSet {
            UserDefaults.standard.set(false, forKey: DefaultsKey.wifiEnabled)
            applyWiFiState()
        }
    }
    @Published var wifiAuto: Bool {
        didSet { UserDefaults.standard.set(false, forKey: DefaultsKey.wifiAuto) }
    }
    @Published var wifiCode: String {
        didSet {
            UserDefaults.standard.set(wifiCode, forKey: DefaultsKey.wifiCode)
            server.code = wifiCode
        }
    }

    @Published var isSyncing = false
    @Published var statusMessage = "Синхронизация ещё не выполнялась"
    @Published var lastSync: Date?
    @Published var lastError: String?

    // Оставлены для будущего возврата Wi-Fi, но не запускаются.
    let server = WiFiSyncServer()
    let browser = WiFiBrowser()

    private var store: Store?
    private var didConfigure = false

    // Realtime-обмен через GitHub
    private var realtimeTask: Task<Void, Never>?
    private var credentialsTask: Task<Void, Never>?
    private var githubETag: String?
    private var remoteSHA: String?
    private var pendingPush = false
    private var pendingPushDate: Date?
    private var lastPushDate: Date = .distantPast
    private var lastPollDate: Date = .distantPast
    /// Идёт запрос к GitHub: опрос и отправка не выполняются одновременно.
    private var busy = false
    /// Пока применяем чужие данные, не отправляем их обратно.
    private var suppressAutoPush = false
    /// После 403/429 опрос приостанавливается, чтобы не расходовать лимит.
    private var rateLimitedUntil: Date?

    init() {
        let defaults = UserDefaults.standard
        githubRepo = defaults.string(forKey: DefaultsKey.repo) ?? "R3G1ST/turno-sync"
        githubToken = defaults.string(forKey: DefaultsKey.token) ?? ""
        autoGitHub = defaults.object(forKey: DefaultsKey.autoGitHub) as? Bool ?? true
        wifiEnabled = false
        wifiAuto = false
        if let stored = defaults.string(forKey: DefaultsKey.wifiCode), stored.count >= 4 {
            wifiCode = stored
        } else {
            let fresh = Self.makeCode()
            wifiCode = fresh
            defaults.set(fresh, forKey: DefaultsKey.wifiCode)
        }
        server.code = wifiCode
    }

    // MARK: Настройка

    func configure(store: Store) {
        guard !didConfigure else { return }
        didConfigure = true
        self.store = store
        // Любое сохранение данных — повод отправить изменения на GitHub.
        store.onDataSaved = { [weak self] in self?.noteLocalChange() }

        server.handleSnapshot = { [weak self] remote in
            guard let self, let store = self.store else { return remote }
            let merged = store.merged(with: remote)
            store.applySyncSnapshot(merged)
            self.lastSync = Date()
            self.lastError = nil
            self.statusMessage = "Синхронизировано по Wi-Fi"
            return store.syncSnapshot()
        }
        server.code = wifiCode
        // Wi-Fi-приём больше не запускаем, но код сохраняем на будущее.
        applyWiFiState()
        ensureRealtime()
    }

    func appDidBecomeActive() {
        guard store != nil else { return }
        guard autoGitHub, githubConfigured, isInitialized else { return }
        ensureRealtime()
        // Сразу проверяем GitHub, не дожидаясь такта цикла.
        Task { [weak self] in await self?.pollOnce() }
    }

    func appDidEnterBackground() {
        stopRealtime()
    }

    // MARK: GitHub

    var githubConfigured: Bool {
        !githubRepo.trimmingCharacters(in: .whitespaces).isEmpty
            && !githubToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isInitialized: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.initialized)
    }

    private func markInitialized() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.initialized)
    }

    func syncNow() {
        markInitialized()
        runManual(.merge)
    }

    func downloadNow() {
        markInitialized()
        runManual(.download)
    }

    func uploadNow() {
        markInitialized()
        runManual(.upload)
    }

    /// Ручное действие ждёт завершения текущего фонового обмена, а не пропускается.
    private func runManual(_ direction: Direction) {
        Task { [weak self] in
            guard let self else { return }
            var waited = 0
            while self.busy, waited < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            await self.syncGitHub(direction, silent: false)
        }
    }

    /// Пользователь изменил репозиторий или токен: через полторы секунды
    /// (когда ввод закончен) перезапускаем обмен с новыми настройками.
    private func credentialsChanged() {
        credentialsTask?.cancel()
        credentialsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.githubETag = nil
            self.remoteSHA = nil
            guard self.githubConfigured, self.isInitialized else { return }
            self.ensureRealtime()
            await self.pollOnce()
        }
    }

    // MARK: Realtime-цикл

    private func ensureRealtime() {
        guard didConfigure, realtimeTask == nil else { return }
        guard autoGitHub, githubConfigured, isInitialized else { return }
        realtimeTask = Task { [weak self] in
            await self?.realtimeLoop()
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    /// Каждые 0,2 с проверяем, не пора ли отправить правку (через 0,4 с после
    /// изменения) или опросить GitHub (раз в секунду). Опрос идёт с ETag,
    /// поэтому ответы 304 не тратят лимит запросов.
    private func realtimeLoop() async {
        while !Task.isCancelled {
            if !busy {
                let now = Date()
                if let until = rateLimitedUntil, now < until {
                    // Пауза после ограничения GitHub.
                } else if pendingPush,
                          let due = pendingPushDate, now >= due,
                          now.timeIntervalSince(lastPushDate) >= 1.0 {
                    await pushOnce()
                } else if now.timeIntervalSince(lastPollDate) >= 1.0 {
                    await pollOnce()
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        realtimeTask = nil
    }

    private func makeClient() -> GitHubClient {
        GitHubClient(
            repo: githubRepo.trimmingCharacters(in: .whitespaces),
            token: githubToken.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Один опрос GitHub. Изменения сразу сливаются и применяются.
    private func pollOnce() async {
        guard let store, !store.loadFailed, !busy,
              autoGitHub, githubConfigured, isInitialized else { return }
        if let until = rateLimitedUntil, Date() < until { return }

        lastPollDate = Date()
        busy = true
        defer { busy = false }

        do {
            switch try await makeClient().load(ifNoneMatch: githubETag) {
            case .notModified(let etag):
                if let etag { githubETag = etag }
                markFirstContact()
                if lastError != nil {
                    lastError = nil
                    statusMessage = "GitHub: синхронизировано \(Self.timeText(Date()))"
                }
            case .remote(let remote):
                githubETag = remote.etag
                remoteSHA = remote.sha
                handleRemote(remote.data)
                markFirstContact()
                if lastError != nil {
                    lastError = nil
                    statusMessage = "GitHub: синхронизировано \(Self.timeText(Date()))"
                }
            }
        } catch SyncError.rateLimited {
            pauseForRateLimit()
        } catch SyncError.notFound {
            // Файла ещё нет: не ошибка, отправим его при следующей правке.
            lastError = nil
        } catch {
            let text = error.localizedDescription
            if lastError != text { lastError = text }
        }
    }

    /// Первый успешный ответ GitHub показываем как состоявшуюся синхронизацию,
    /// даже если данные не изменились.
    private func markFirstContact() {
        guard lastSync == nil else { return }
        lastSync = Date()
        statusMessage = "GitHub: синхронизировано \(Self.timeText(Date()))"
    }

    /// Применяет изменения с GitHub и решает, нужно ли что-то отправить обратно.
    private func handleRemote(_ remote: Store.AppData) {
        guard let store else { return }
        let before = store.data
        let merged = store.merged(with: remote)
        let changedLocally = !Self.sameSyncState(before, merged)

        if changedLocally {
            suppressAutoPush = true
            store.applySyncSnapshot(merged)
            suppressAutoPush = false
            lastSync = Date()
            statusMessage = "GitHub: получены изменения \(Self.timeText(Date()))"
        }

        // Если после слияния у этого устройства есть то, чего нет на GitHub,
        // отправляем объединённый снимок.
        if !Self.sameSyncState(merged, remote) {
            schedulePush(after: 0.2)
        }
    }

    /// Отправка изменений. Не чаще одного PUT в секунду.
    private func pushOnce() async {
        guard let store, !store.loadFailed, !busy,
              autoGitHub, githubConfigured, isInitialized else { return }
        if let until = rateLimitedUntil, Date() < until {
            pendingPushDate = until
            return
        }

        pendingPush = false
        pendingPushDate = nil
        busy = true
        defer {
            busy = false
            lastPushDate = Date()
        }

        let client = makeClient()
        do {
            var sha = remoteSHA
            if sha == nil {
                // Первый обмен: узнаём sha существующего файла и попутно
                // подтягиваем чужие изменения, чтобы ничего не перезаписать.
                if case .remote(let current) = try await client.load() {
                    githubETag = current.etag
                    remoteSHA = current.sha
                    sha = current.sha
                    let merged = store.merged(with: current.data)
                    if !Self.sameSyncState(merged, current.data) {
                        suppressAutoPush = true
                        store.applySyncSnapshot(merged)
                        suppressAutoPush = false
                    }
                }
            }

            let snapshot = store.syncSnapshot()
            let freshSHA = try await client.save(snapshot, sha: sha)
            if !freshSHA.isEmpty { remoteSHA = freshSHA }
            // После PUT у файла новый ETag — заберём его следующим опросом.
            githubETag = nil
            lastSync = Date()
            lastError = nil
            statusMessage = "GitHub: отправлено \(Self.timeText(Date()))"
        } catch SyncError.conflict {
            // Кто-то успел записать файл раньше: перечитаем и сольём.
            githubETag = nil
            remoteSHA = nil
            pendingPush = true
            pendingPushDate = Date()
        } catch SyncError.rateLimited {
            pauseForRateLimit()
            pendingPush = true
            pendingPushDate = rateLimitedUntil
        } catch {
            let text = error.localizedDescription
            if lastError != text { lastError = text }
            pendingPush = true
            pendingPushDate = Date().addingTimeInterval(5)
        }
    }

    private func schedulePush(after delay: TimeInterval) {
        guard autoGitHub, githubConfigured, isInitialized else { return }
        pendingPush = true
        pendingPushDate = Date().addingTimeInterval(delay)
        ensureRealtime()
    }

    private func noteLocalChange() {
        guard !suppressAutoPush else { return }
        schedulePush(after: 0.4)
    }

    private func pauseForRateLimit() {
        rateLimitedUntil = Date().addingTimeInterval(300)
        lastError = SyncError.rateLimited.localizedDescription
        statusMessage = "GitHub: пауза из-за лимита запросов"
    }

    /// Ручная синхронизация: полное чтение, слияние и (при необходимости) запись.
    private func syncGitHub(_ direction: Direction, silent: Bool) async {
        guard let store else { return }
        guard !store.loadFailed else {
            lastError = "Локальные данные не загрузились — синхронизация остановлена, чтобы ничего не перезаписать. Восстановите файл из папки Backups."
            return
        }
        if direction == .upload, store.data.employees.isEmpty, store.data.shifts.isEmpty {
            lastError = "На этом устройстве нет данных — загрузка отменена, чтобы не стереть данные на другом."
            return
        }
        guard githubConfigured else {
            if !silent { lastError = SyncError.notConfigured.localizedDescription }
            return
        }
        guard !busy else { return }

        busy = true
        isSyncing = true
        defer {
            busy = false
            isSyncing = false
            lastPushDate = Date()
            ensureRealtime()
        }
        if !silent {
            statusMessage = "Связываемся с GitHub…"
            lastError = nil
        }

        do {
            let client = makeClient()
            let remote = try await client.load()
            githubETag = remote.etag
            remoteSHA = remote.sha

            let merged: Store.AppData
            switch direction {
            case .merge:
                merged = store.merged(with: remote.data)
            case .download:
                merged = store.adopting(remote.data)
            case .upload:
                merged = store.authoritative(over: remote.data)
            }
            suppressAutoPush = true
            store.applySyncSnapshot(merged)
            suppressAutoPush = false

            let current = store.syncSnapshot()
            let needsUpload = direction == .upload || !Self.sameSyncState(current, remote.data)

            if needsUpload {
                do {
                    let freshSHA = try await client.save(current, sha: remote.sha)
                    if !freshSHA.isEmpty { remoteSHA = freshSHA }
                    githubETag = nil
                } catch SyncError.conflict {
                    // Кто-то успел изменить файл — один раз перечитываем и сливаем.
                    let fresh = try await client.load()
                    githubETag = fresh.etag
                    remoteSHA = fresh.sha
                    let retry = store.merged(with: fresh.data)
                    suppressAutoPush = true
                    store.applySyncSnapshot(retry)
                    suppressAutoPush = false
                    let freshSHA = try await client.save(store.syncSnapshot(), sha: fresh.sha)
                    if !freshSHA.isEmpty { remoteSHA = freshSHA }
                    githubETag = nil
                }
            }

            markInitialized()
            lastSync = Date()
            lastError = nil
            statusMessage = "GitHub: синхронизировано \(Self.timeText(Date()))"
        } catch SyncError.rateLimited {
            pauseForRateLimit()
        } catch {
            lastError = error.localizedDescription
            if !silent {
                statusMessage = "GitHub: ошибка"
            }
        }
    }

    /// Сравнение без служебных полей (deviceID, seen, updatedAt).
    private static func sameSyncState(_ a: Store.AppData, _ b: Store.AppData) -> Bool {
        a.hasSameContent(as: b)
            && a.syncStamps == b.syncStamps
            && a.syncTombstones == b.syncTombstones
    }

    // MARK: Wi-Fi (временно отключено)

    /// Wi-Fi-сервер и поиск не запускаются — синхронизация идёт через GitHub.
    func applyWiFiState() {
        server.stop()
        browser.stop()
    }

    func refreshWiFi() {
        applyWiFiState()
    }

    func stopSearch() {
        browser.stop()
    }

    func regenerateWiFiCode() {
        wifiCode = Self.makeCode()
        server.status = "Wi-Fi временно отключён"
    }

    func syncWiFi(to peer: WiFiPeer) {
        lastError = "Wi-Fi-синхронизация временно отключена. Используйте GitHub."
    }

    // MARK: Прочее

    private static func makeCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: date)
    }

    var lastSyncText: String {
        guard let lastSync else { return "ещё не было" }
        return Self.timeText(lastSync)
    }
}
