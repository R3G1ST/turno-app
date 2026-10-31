import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Кроссплатформенные алиасы

#if os(macOS)
/// Шрифт: NSFont на macOS, UIFont на iOS (одинаковые API системного шрифта).
typealias PlatformFont = NSFont
/// Цвет: NSColor на macOS, UIColor на iOS.
typealias PlatformColor = NSColor
#else
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

// MARK: - Помощник «Поделиться файлом» (iOS)

#if os(iOS)
/// Показывает системную шторку «Поделиться» для файла/данных.
/// На macOS вместо неё используются NSSavePanel/PDF-печать, поэтому здесь только iOS.
enum ShareFile {
    /// Найти root-контроллер активного окна.
    private static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        return window?.rootViewController
    }

    /// Найти верхний представленный контроллер (чтобы шторка не «прилипла» под sheet).
    private static func topPresented(_ start: UIViewController?) -> UIViewController? {
        guard let presented = start?.presentedViewController else { return start }
        return topPresented(presented)
    }

    /// Предоставить данные как временный файл и открыть шторку «Поделиться».
    static func present(data: Data, fileName: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: tmp)
        guard let presenter = topPresented(rootViewController) else { return }
        let activity = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        // iPad: якорь для поповера.
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                    y: presenter.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
}
#endif
