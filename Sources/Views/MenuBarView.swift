import SwiftUI

public struct MenuBarView: View {
    var sessionManager: SessionManager
    var updateChecker: UpdateChecker? = nil
    @State private var selectedSession: AgentSession? = nil
    // MenuBarExtra windows cannot be drag-resized on macOS, so the size is a
    // persisted preference instead.
    @AppStorage("windowSize") private var windowSize: String = WindowSize.medium.rawValue

    enum WindowSize: String, CaseIterable {
        case small = "S"
        case medium = "M"
        case large = "L"

        var width: CGFloat {
            switch self {
            case .small: return 320
            case .medium: return 380
            case .large: return 440
            }
        }

        var listHeight: CGFloat {
            switch self {
            case .small: return 300
            case .medium: return 480
            case .large: return 700
            }
        }
    }

    private var size: WindowSize { WindowSize(rawValue: windowSize) ?? .medium }

    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return "\(n / 1_000)k"
        default: return String(n)
        }
    }

    struct LimitRow {
        let provider: AgentProvider
        let limits: [ProviderLimit]
    }

    // Providers with known account limits, stable order, tightest-first gauges
    @MainActor
    private var limitRows: [LimitRow] {
        AgentProvider.allCases.compactMap { provider in
            guard var limits = sessionManager.providerLimits[provider], !limits.isEmpty else { return nil }
            // Show the model-scoped weekly gauge only when it's the tighter constraint
            if let all = limits.first(where: { $0.kind == "weekly_all" }),
               let scoped = limits.first(where: { $0.kind == "weekly_scoped" }),
               scoped.percent <= all.percent {
                limits.removeAll { $0.kind == "weekly_scoped" }
            }
            return LimitRow(provider: provider, limits: limits)
        }
    }

    private func limitColor(_ percent: Double) -> Color {
        switch percent {
        case 85...: return .red
        case 60...: return .orange
        default: return .secondary
        }
    }

    private func resetText(_ limit: ProviderLimit) -> String? {
        guard let date = limit.resetsAt else { return nil }
        let mins = Int(date.timeIntervalSinceNow / 60)
        guard mins > 0 else { return nil }
        if mins >= 1440 { return "↻\(mins / 1440)d" }
        if mins >= 60 { return "↻\(mins / 60)h\(mins % 60)m" }
        return "↻\(mins)m"
    }

    @ViewBuilder
    private func limitLine(_ row: LimitRow) -> some View {
        HStack(spacing: 4) {
            Text(row.provider.displayName)
                .foregroundStyle(.secondary)
            ForEach(row.limits) { limit in
                Text("\(limit.shortLabel) \(Int(limit.percent))%")
                    .foregroundStyle(limitColor(limit.percent))
                    .fontWeight(limit.percent >= 85 ? .semibold : .regular)
                if limit.kind == "session", let reset = resetText(limit) {
                    Text(reset)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.caption2)
    }

    public init(sessionManager: SessionManager, updateChecker: UpdateChecker? = nil) {
        self.sessionManager = sessionManager
        self.updateChecker = updateChecker
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let selected = selectedSession, let session = sessionManager.sessions.first(where: { $0.id == selected.id }) {
                DetailPopover(
                    session: session,
                    onFocus: {
                        TerminalFocusHelper.focusTerminal(forPid: session.pid)
                    },
                    onDismiss: {
                        selectedSession = nil
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SessionHawk")
                            .font(.headline)
                            .fontWeight(.bold)
                        if let daily = sessionManager.dailyStats {
                            Text("Today: \(Self.compact(daily.outputTokens)) tokens · \(daily.turns) turns")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(limitRows, id: \.provider) { row in
                            limitLine(row)
                        }
                    }

                    Spacer()

                    Text("\(sessionManager.sessions.count) active session\(sessionManager.sessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()

                if let checker = updateChecker, let newVersion = checker.updateAvailable {
                    Button {
                        NSWorkspace.shared.open(checker.releaseURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Update available — v\(newVersion)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15))
                    }
                    .buttonStyle(.plain)

                    Divider()
                }

                if sessionManager.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "eyes")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No active agent sessions")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("Run sessionhawk-hook.sh in your terminal to monitor sessions.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(height: 180)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(sessionManager.sessions) { session in
                                SessionRowView(
                                    session: session,
                                    onFocus: {
                                        selectedSession = session
                                    }
                                )
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: size.listHeight)
                }
                
                Divider()
                
                HStack {
                    // Left: quiet Quit
                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        Label("Quit", systemImage: "power")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit SessionHawk")

                    Spacer()

                    // Center: external links as small capsule chips
                    HStack(spacing: 8) {
                        FooterChip(
                            icon: "star.fill", iconColor: .yellow, label: "Star",
                            help: "Star SessionHawk on GitHub — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")",
                            url: "https://github.com/jcsuen/SessionHawk"
                        )
                        FooterChip(
                            icon: "cup.and.saucer.fill", iconColor: .orange, label: "Coffee",
                            help: "Enjoying SessionHawk? Buy me a coffee",
                            url: "https://buymeacoffee.com/jcsuen"
                        )
                        FooterChip(
                            icon: "trophy.fill", iconColor: .purple, label: "Board",
                            help: "Daily leaderboard — who's flying the most agents today",
                            url: "https://paulobuilds.com/sessionhawk/leaderboard"
                        )
                    }

                    Spacer()

                    // Right: window size selector
                    Picker("", selection: $windowSize) {
                        ForEach(WindowSize.allCases, id: \.rawValue) { s in
                            Text(s.rawValue).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                    .help("Window size")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: size.width)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedSession?.id)
    }
}

/// Small capsule chip for external links in the footer, with a hover tint.
struct FooterChip: View {
    let icon: String
    let iconColor: Color
    let label: String
    let help: String
    let url: String
    @State private var hovered = false

    var body: some View {
        Button {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(hovered ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
