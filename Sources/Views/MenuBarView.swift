import SwiftUI

public struct MenuBarView: View {
    var sessionManager: SessionManager
    var updateChecker: UpdateChecker? = nil
    @State private var selectedSession: AgentSession? = nil
    @State private var showHistory = false
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

    // Token counts mean nothing to most people — translate to words/novels.
    // A token is ~¾ of an English word; a novel ~90k words.
    static func tokensInWords(_ tokens: Int) -> String {
        let words = tokens * 3 / 4
        let novels = Double(words) / 90_000
        if novels >= 1 {
            return "≈ \(compact(words)) words — about \(novels < 10 ? String(format: "%.1f", novels) : String(Int(novels))) novels' worth of text"
        }
        return "≈ \(compact(words)) words of generated text"
    }

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
        if mins >= 1440 {
            let h = (mins % 1440) / 60
            return "↻\(mins / 1440)d" + (h > 0 ? "\(h)h" : "")
        }
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
                // weekly_all and weekly_scoped share a reset — show it once
                if limit.kind != "weekly_scoped", let reset = resetText(limit) {
                    Text(reset)
                        .foregroundStyle(.tertiary)
                }
                // Pace warning only when burning ahead of a steady window burn;
                // reserve details live in the tooltip to keep the row calm
                if let pace = limit.paceReserve(), pace < 0 {
                    Text("\(-pace)% over pace")
                        .foregroundStyle(.red)
                }
            }
        }
        .font(.caption2)
        .help(paceSummary(row))
    }

    // Tooltip: full pace story per gauge, codexbar-style
    private func paceSummary(_ row: LimitRow) -> String {
        row.limits.compactMap { limit -> String? in
            guard let pace = limit.paceReserve() else { return nil }
            let state = pace >= 0 ? "\(pace)% in reserve" : "\(-pace)% over pace"
            return "\(limit.shortLabel): \(Int(limit.percent))% used, \(state) vs steady burn"
        }.joined(separator: "\n")
    }

    // Needs-you-first ordering: waiting (and errored) sessions on top, then
    // working, then idle. firstSeen tie-break keeps rows from jumping around
    // on every heartbeat.
    @MainActor
    private var orderedSessions: [AgentSession] {
        sessionManager.sessions.sorted {
            (Self.statePriority($0.state), $0.firstSeen) < (Self.statePriority($1.state), $1.firstSeen)
        }
    }

    public static func statePriority(_ state: SessionState) -> Int {
        switch state {
        case .waitingForInput: return 0
        case .error: return 1
        case .working: return 2
        case .idle: return 3
        }
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
            } else if showHistory, let store = sessionManager.historyStore {
                HistoryPanel(store: store, onDismiss: { showHistory = false })
                    .frame(height: size.listHeight + 120)
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
                                .help(Self.tokensInWords(daily.outputTokens))
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
                        Text("Sessions appear when a Claude Code, Codex, or Gemini CLI is running.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Text("Claude sessions started before install: run /hooks once (or restart them).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(height: 180)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(orderedSessions) { session in
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

                    // Right: history + config folder + window size selector
                    if sessionManager.historyStore != nil {
                        Button(action: { showHistory = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Session history — recent sessions and per-day totals (stored locally)")
                    }
                    Button(action: { ConfigFolder.open() }) {
                        Image(systemName: "gearshape")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open ~/.sessionhawk — all options documented in CONFIG.md there")

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
