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
        }
    }
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

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 25
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Turno/1.0.17", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    func load() async throws -> (data: Store.AppData, sha: String) {
        guard !repo.isEmpty, !token.isEmpty else { throw SyncError.notConfigured }
        guard let url = contentsURL else { throw SyncError.notConfigured }
        let (raw, response) = try await URLSession.shared.data(for: request(url))
        guard let http = response as? HTTPURLResponse else { throw SyncError.badData }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw SyncError.unauthorized
        case 404: throw SyncError.notFound
        default: throw SyncError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let content = obj["content"] as? String,
              let sha = obj["sha"] as? String,
              let decoded = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: ""))
        else { throw SyncError.badData }
        return (try SyncCodec.decode(decoded), sha)
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
        let (answer, response) = try await URLSession.shared.data(for: request(url, method: "PUT", body: bodyData))
        guard let http = response as? HTTPURLResponse else { throw SyncError.badData }
        switch http.statusCode {
        case 200, 201:
            let obj = try? JSONSerialization.jsonObject(with: answer) as? [String: Any]
            let content = obj?["content"] as? [String: Any]
            return content?["sha"] as? String ?? ""
        case 401, 403: throw SyncError.unauthorized
        case 409, 422: throw SyncError.conflict
        default: throw SyncError.http(http.statusCode)
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
        static let wifiEnabled = "turno.sync.wifi.enabled"
        static let wifiCode = "turno.sync.wifi.code"
        static let wifiAuto = "turno.sync.wifi.auto"
        static let wifiInitialized = "turno.sync.wifi.initialized"
    }

    @Published var githubRepo: String {
        didSet { UserDefaults.standard.set(githubRepo, forKey: DefaultsKey.repo) }
    }
    @Published var githubToken: String {
        didSet { UserDefaults.standard.set(githubToken, forKey: DefaultsKey.token) }
    }
    @Published var autoGitHub: Bool {
        didSet { UserDefaults.standard.set(autoGitHub, forKey: DefaultsKey.autoGitHub) }
    }
    @Published var wifiEnabled: Bool {
        didSet {
            UserDefaults.standard.set(wifiEnabled, forKey: DefaultsKey.wifiEnabled)
            applyWiFiState()
        }
    }
    @Published var wifiAuto: Bool {
        didSet { UserDefaults.standard.set(wifiAuto, forKey: DefaultsKey.wifiAuto) }
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

    let server = WiFiSyncServer()
    let browser = WiFiBrowser()

    private var store: Store?
    private var debounceTask: Task<Void, Never>?
    private var wifiAutoTask: Task<Void, Never>?
    private var didConfigure = false
    private var lastAutoAttempt: Date = .distantPast

    init() {
        let defaults = UserDefaults.standard
        githubRepo = defaults.string(forKey: DefaultsKey.repo) ?? "R3G1ST/turno-sync"
        githubToken = defaults.string(forKey: DefaultsKey.token) ?? ""
        autoGitHub = defaults.object(forKey: DefaultsKey.autoGitHub) as? Bool ?? true
        wifiEnabled = defaults.object(forKey: DefaultsKey.wifiEnabled) as? Bool ?? true
        wifiAuto = defaults.object(forKey: DefaultsKey.wifiAuto) as? Bool ?? true
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
        store.onDataSaved = { [weak self] in self?.scheduleAutoSync() }

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
        #if os(macOS)
        applyWiFiState()
        #endif
    }

    func appDidBecomeActive() {
        guard let store else { return }
        // При открытии приложения подтягиваем свежие данные, но не чаще раза в минуту.
        if autoGitHub, githubConfigured, isInitialized,
           Date().timeIntervalSince(lastAutoAttempt) > 60 {
            lastAutoAttempt = Date()
            Task { await syncGitHub(.merge, silent: true) }
        }
        #if os(macOS)
        if wifiEnabled, !server.isRunning, store.data.syncUpdatedAt != nil {
            applyWiFiState()
        }
        #else
        // Автосинхронизация по Wi-Fi — только если пользователь уже спарил устройства.
        if wifiEnabled, wifiAuto,
           UserDefaults.standard.bool(forKey: DefaultsKey.wifiInitialized),
           wifiCode.count >= 4, !isSyncing {
            browser.stop()
            browser.start()
            wifiAutoTask?.cancel()
            wifiAutoTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, let self, let peer = self.browser.peers.first else { return }
                self.syncWiFi(to: peer)
            }
        }
        #endif
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
        Task { await syncGitHub(.merge, silent: false) }
    }

    func downloadNow() {
        markInitialized()
        Task { await syncGitHub(.download, silent: false) }
    }

    func uploadNow() {
        markInitialized()
        Task { await syncGitHub(.upload, silent: false) }
    }

    private func scheduleAutoSync() {
        guard autoGitHub, githubConfigured, isInitialized else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncGitHub(.merge, silent: true)
        }
    }

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
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        if !silent {
            statusMessage = "Связываемся с GitHub…"
            lastError = nil
        }

        do {
            let client = GitHubClient(
                repo: githubRepo.trimmingCharacters(in: .whitespaces),
                token: githubToken.trimmingCharacters(in: .whitespaces)
            )
            let (remote, sha) = try await client.load()

            let merged: Store.AppData
            switch direction {
            case .merge:
                merged = store.merged(with: remote)
            case .download:
                merged = store.adopting(remote)
            case .upload:
                merged = store.authoritative(over: remote)
            }
            store.applySyncSnapshot(merged)

            let current = store.syncSnapshot()
            let needsUpload = direction == .upload
                || !current.hasSameContent(as: remote)
                || current.syncStamps != remote.syncStamps
                || current.syncTombstones != remote.syncTombstones

            if needsUpload {
                do {
                    _ = try await client.save(current, sha: sha)
                } catch SyncError.conflict {
                    // Кто-то успел изменить файл — один раз перечитываем и сливаем.
                    let (freshRemote, freshSHA) = try await client.load()
                    let retry = store.merged(with: freshRemote)
                    store.applySyncSnapshot(retry)
                    _ = try await client.save(store.syncSnapshot(), sha: freshSHA)
                }
            }

            markInitialized()
            lastSync = Date()
            lastError = nil
            statusMessage = "GitHub: синхронизировано \(Self.timeText(Date()))"
        } catch {
            lastError = error.localizedDescription
            if !silent {
                statusMessage = "GitHub: ошибка"
            }
        }
    }

    // MARK: Wi-Fi

    func applyWiFiState() {
        #if os(macOS)
        if wifiEnabled {
            server.code = wifiCode
            server.start()
        } else {
            server.stop()
        }
        #else
        // На iPhone приём не нужен — только поиск Mac.
        if wifiEnabled {
            browser.start()
        } else {
            browser.stop()
        }
        #endif
    }

    func refreshWiFi() {
        applyWiFiState()
    }

    func stopSearch() {
        browser.stop()
    }

    func regenerateWiFiCode() {
        wifiCode = Self.makeCode()
        server.status = server.isRunning ? "Ждём iPhone…" : "Выключен"
    }

    func syncWiFi(to peer: WiFiPeer) {
        guard let store else { return }
        guard !store.loadFailed else {
            lastError = "Локальные данные не загрузились — синхронизация остановлена, чтобы ничего не перезаписать."
            return
        }
        guard wifiCode.count >= 4 else {
            lastError = "Введите код подключения с Mac"
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        statusMessage = "Синхронизация с \(peer.name)…"
        Task {
            defer { isSyncing = false }
            do {
                let payload = try SyncCodec.encode(store.syncSnapshot())
                let answer = try await WiFiSyncClient.exchange(
                    endpoint: peer.endpoint, code: wifiCode, payload: payload)
                let raw = try SyncCrypto.open(answer, code: wifiCode)
                let remote = try SyncCodec.decode(raw)
                let merged = store.merged(with: remote)
                store.applySyncSnapshot(merged)
                UserDefaults.standard.set(true, forKey: DefaultsKey.wifiInitialized)
                lastSync = Date()
                lastError = nil
                statusMessage = "Wi-Fi: синхронизировано \(Self.timeText(Date()))"
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Wi-Fi: ошибка"
            }
        }
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
