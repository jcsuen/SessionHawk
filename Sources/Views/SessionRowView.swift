import SwiftUI

/// Status badge tuned for translucent menu bar backdrops: solid fills with
/// guaranteed-contrast text instead of colored text over colored translucency.
struct StatusBadge: View {
    let state: SessionState

    var body: some View {
        HStack(spacing: 5) {
            if let dot = dotColor {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
    }

    private var label: String {
        switch state {
        case .waitingForInput: return "Input Needed"
        case .working: return "Working"
        case .error: return "Error"
        case .idle: return "Idle"
        }
    }

    // Solid high-contrast pill for attention states; subtle neutral pill with
    // a colored dot for the rest.
    private var background: Color {
        switch state {
        case .waitingForInput: return .orange
        case .error: return .red
        default: return Color.primary.opacity(0.08)
        }
    }

    private var textColor: Color {
        switch state {
        case .waitingForInput: return .black
        case .error: return .white
        case .working: return .primary
        case .idle: return .secondary
        }
    }

    private var dotColor: Color? {
        switch state {
        case .working: return .green
        case .idle: return .secondary
        default: return nil
        }
    }
}

public struct SessionRowView: View {
    let session: AgentSession
    let onFocus: () -> Void

    public init(session: AgentSession, onFocus: @escaping () -> Void) {
        self.session = session
        self.onFocus = onFocus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.provider.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("PID \(String(session.pid))")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                StatusBadge(state: session.state)
            }

            if let dir = session.workingDirectory {
                pathText(dir)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let tokenUsage = session.tokenUsage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                                Capsule()
                                    .fill(tokenUsage.usagePercentage > 80 ? Color.red : Color.accentColor)
                                    .frame(width: max(4, geo.size.width * min(tokenUsage.usagePercentage, 100) / 100))
                            }
                        }
                        .frame(height: 4)

                        Text("\(Int(tokenUsage.usagePercentage))%")
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }

                    Text("\(tokenUsage.inputTokens + tokenUsage.outputTokens, format: .number) / \(tokenUsage.totalLimit, format: .number) tokens")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onFocus()
        }
    }

    /// Dim the parent path, highlight the folder name.
    private func pathText(_ dir: String) -> Text {
        let url = URL(fileURLWithPath: dir)
        let folder = url.lastPathComponent
        let parent = url.deletingLastPathComponent().path
        guard !folder.isEmpty, parent != dir else {
            return Text(dir).foregroundStyle(.secondary)
        }
        return Text(parent == "/" ? "/" : parent + "/")
            .foregroundStyle(.secondary)
        + Text(folder)
            .foregroundStyle(.primary)
    }
}
