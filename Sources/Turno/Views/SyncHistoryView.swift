import SwiftUI

/// История версий файла синхронизации на GitHub и откат на выбранную дату.
struct SyncHistoryView: View {
    @EnvironmentObject var sync: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var pending: GitHubCommit?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        #if os(macOS)
        .frame(width: 520, height: 460)
        #endif
        .onAppear { sync.loadHistory() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Откатить данные", role: .destructive) {
                if let commit = pending {
                    sync.rollback(to: commit)
                    dismiss()
                }
                pending = nil
            }
            Button("Отмена", role: .cancel) { pending = nil }
        } message: {
            Text("Все изменения после этой версии будут удалены на обоих устройствах. Перед заменой автоматически создаётся резервная копия.")
        }
    }

    private var confirmationTitle: String {
        guard let pending else { return "" }
        return "Откатить на \(Self.dayFormatter.string(from: pending.date))?"
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("История версий")
                    .font(.headline)
                Text("Файл turno.json на GitHub. Можно вернуть данные на любую из последних версий.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if sync.isLoadingHistory {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Haptics.tap()
                    sync.loadHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Обновить историю")
            }
            Button("Закрыть") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if let error = sync.historyError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Повторить") { sync.loadHistory() }
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sync.history.isEmpty {
            VStack(spacing: 10) {
                if sync.isLoadingHistory {
                    ProgressView()
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("История пока пуста")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sync.history) { commit in
                        row(commit)
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    private func row(_ commit: GitHubCommit) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dayFormatter.string(from: commit.date))
                    .font(.callout.weight(.semibold))
                Text(commit.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(commit.author)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button("Откатить") {
                Haptics.select()
                pending = commit
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
