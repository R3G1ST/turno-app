import SwiftUI

/// Компактный индикатор синхронизации: состояние, иконка и переход в настройки.
struct SyncBadge: View {
    @EnvironmentObject var sync: SyncManager

    var compact = false
    var action: () -> Void = {}

    private var color: Color {
        switch sync.indicator {
        case .synced: return .green
        case .conflict: return .orange
        case .error: return .red
        case .waiting: return .orange
        case .syncing, .sending: return .blue
        case .off, .idle: return .secondary
        }
    }

    private var isActive: Bool {
        sync.indicator == .syncing || sync.indicator == .sending
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: sync.indicatorIcon)
                    .symbolEffect(.pulse, isActive: isActive)
                if !compact {
                    Text(sync.indicatorText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(
                Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Синхронизация: \(sync.indicatorText). Нажмите, чтобы открыть настройки.")
    }
}
