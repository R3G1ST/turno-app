import Foundation
import AppKit
import SwiftUI

struct UpdateInfo: Identifiable {
    let id = UUID()
    let version: String
    let notes: String
    let assetURL: URL
}

/// Автообновления через GitHub Releases (R3G1ST/turno-app).
/// Ищет релиз с тегом новее текущей версии и DMG-ассетом Turno-x.y.z.dmg.
@MainActor
final class Updater: ObservableObject {
    static let repo = "R3G1ST/turno-app"
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    @Published var updateInfo: UpdateInfo?
    @Published var isInstalling = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var lastCheckDone = false

    func checkSilent() { Task { await check(showNoUpdate: false) } }
    func checkManual() { Task { await check(showNoUpdate: true) } }

    private func check(showNoUpdate: Bool) async {
        errorMessage = nil
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tagVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            lastCheckDone = true
            if isNewer(tagVersion, than: Self.currentVersion),
               let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
               let assetURL = URL(string: dmg.browser_download_url) {
                updateInfo = UpdateInfo(version: tagVersion, notes: release.body ?? "", assetURL: assetURL)
            } else if showNoUpdate {
                let a = NSAlert()
                a.messageText = "Обновлений нет"
                a.informativeText = "У вас последняя версия Turno (\(Self.currentVersion))."
                a.runModal()
            }
        } catch {
            if showNoUpdate {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    // MARK: - Установка

    func install(_ info: UpdateInfo) {
        isInstalling = true
        progress = 0
        errorMessage = nil
        Task {
            do {
                let dmgURL = try await download(info.assetURL)
                let mounted = try mount(dmgURL)
                defer { try? unmount(mounted) }

                let appInDmg = mounted.appendingPathComponent("Turno.app")
                guard FileManager.default.fileExists(atPath: appInDmg.path) else {
                    throw UpdaterError.badImage
                }
                progress = 0.85

                let target = Bundle.main.bundleURL
                let backup = target.deletingLastPathComponent()
                    .appendingPathComponent("Turno-old-\(Int(Date().timeIntervalSince1970)).app")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.moveItem(at: target, to: backup)
                try FileManager.default.copyItem(at: appInDmg, to: target)
                progress = 1

                // Перезапуск новой версии: запуск идёт отдельным процессом с задержкой,
                // чтобы старая копия успела закрыться — иначе macOS не запускает дубликат.
                let script = "sleep 2; open -n '\(target.path)'"
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", script]
                relaunch.standardOutput = FileHandle.nullDevice
                relaunch.standardError = FileHandle.nullDevice
                try relaunch.run()
                // Закрываем старую копию: сначала штатно, затем страховка —
                // иначе старое окно зависает на «Установка… 100%».
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    exit(0)
                }
            } catch {
                isInstalling = false
                errorMessage = "Не удалось обновить: \(error.localizedDescription). Скачайте установщик вручную: github.com/\(Self.repo)/releases"
            }
        }
    }

    private enum UpdaterError: LocalizedError {
        case badImage
        var errorDescription: String? {
            switch self {
            case .badImage: return "В образе нет Turno.app"
            }
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let (tmp, _) = try await URLSession.shared.download(from: url)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Turno-update-\(Int(Date().timeIntervalSince1970)).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        progress = 0.75
        return dest
    }

    private func mount(_ dmg: URL) throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(from: out, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let dev = entities.last(where: { $0["mount-point"] != nil })?["mount-point"] as? String
        else { throw UpdaterError.badImage }
        return URL(fileURLWithPath: dev, isDirectory: true)
    }

    private func unmount(_ url: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["detach", url.path, "-force"]
        try? proc.run()
        proc.waitUntilExit()
    }
}

// MARK: - Модели GitHub API

private struct GitHubRelease: Decodable {
    let tag_name: String
    let body: String?
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
