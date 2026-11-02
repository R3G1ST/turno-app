import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Форматирование сумм

/// Единое форматирование денег: «245 000» (с пробелами между разрядами).
enum Money {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ru_RU")
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    static func grouped(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
    }
}

// MARK: - Тактильная отдача

/// Лёгкая тактильная отдача на iPhone. На маке — тихий no-op.
enum Haptics {
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func select() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: - Кнопки с отдачей

/// Кнопка/карточка, которая пружинисто сжимается при нажатии.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Свайп месяцев

/// Горизонтальный свайп по экрану: влево — следующий месяц, вправо — предыдущий.
/// Вертикальная прокрутка не перехватывается.
struct MonthSwipe: ViewModifier {
    let onSwipe: (Int) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.simultaneousGesture(
            DragGesture(minimumDistance: 18).onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.4 else { return }
                onSwipe(dx < 0 ? 1 : -1)
            }
        )
        #else
        content
        #endif
    }
}

extension View {
    func monthSwipe(_ onSwipe: @escaping (Int) -> Void) -> some View {
        modifier(MonthSwipe(onSwipe: onSwipe))
    }
}

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
