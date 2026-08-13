import SwiftUI

/// Recent-session history: per-day rollups with the day's sessions beneath.
/// Reads straight from HistoryStore on appear — history is written at most
/// once a minute, so there is nothing to observe live.
public struct HistoryPanel: View {
    let store: HistoryStore
    let onDismiss: () -> Void
    @State private var days: [(day: String, rollup: HistoryRollup, records: [HistoryRecord])] = []

    public init(store: HistoryStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
    }

    static func hours(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 { return "\(mins / 60)h\(String(format: "%02d", mins % 60))m" }
        return "\(mins)m"
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("History")
                    .font(.headline)
                Spacer()
                Text("\(HistoryStore.retentionDays)d kept")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("History lives in ~/.sessionhawk/history (plain JSON, never leaves this Mac); days older than \(HistoryStore.retentionDays) are deleted at launch.")
            }
            .padding()

            Divider()

            if days.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No history yet")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Sessions are recorded here as they run — check back after your next agent session.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(days, id: \.day) { entry in
                            dayHeader(entry.day, entry.rollup)
                            ForEach(entry.records) { record in
                                recordRow(record)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        days = store.days(limit: 14).compactMap { day in
            let records = store.records(day: day)
            guard !records.isEmpty else { return nil }
            return (day, HistoryRollup.compute(records), records)
        }
    }

    @ViewBuilder
    private func dayHeader(_ day: String, _ rollup: HistoryRollup) -> some View {
        HStack {
            Text(day == HistoryStore.dayKey(Date()) ? "Today" : day)
                .font(.caption.weight(.semibold))
            Spacer()
            Text("\(rollup.sessionCount) session\(rollup.sessionCount == 1 ? "" : "s") · \(Self.hours(rollup.activeSeconds)) agent time · \(MenuBarView.compact(rollup.outputTokens)) tokens")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help(MenuBarView.tokensInWords(rollup.outputTokens))
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func recordRow(_ record: HistoryRecord) -> some View {
        HStack(spacing: 8) {
            Text(record.projectName)
                .font(.caption)
                .lineLimit(1)
                .help(record.workingDirectory ?? "")
            Text(record.provider.displayName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(Self.hours(record.durationSeconds))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(MenuBarView.compact(record.outputTokens)) tok")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}
