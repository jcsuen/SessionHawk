import Foundation

/// One finished (or snapshotted) agent session as persisted to local history.
/// Everything here stays on disk under ~/.sessionhawk/history — nothing is
/// ever sent anywhere.
public struct HistoryRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public var provider: AgentProvider
    public var workingDirectory: String?
    public var firstSeen: Date
    public var lastActive: Date
    public var outputTokens: Int
    public var turns: Int
    /// Accumulated seconds spent in each state (keyed by SessionState rawValue)
    public var stateSeconds: [String: Double]

    public var projectName: String {
        workingDirectory.map { ($0 as NSString).lastPathComponent } ?? "unknown"
    }

    public var durationSeconds: Double {
        lastActive.timeIntervalSince(firstSeen)
    }

    public init(id: UUID, provider: AgentProvider, workingDirectory: String?,
                firstSeen: Date, lastActive: Date,
                outputTokens: Int, turns: Int, stateSeconds: [String: Double]) {
        self.id = id
        self.provider = provider
        self.workingDirectory = workingDirectory
        self.firstSeen = firstSeen
        self.lastActive = lastActive
        self.outputTokens = outputTokens
        self.turns = turns
        self.stateSeconds = stateSeconds
    }

    public init(from session: AgentSession) {
        self.init(id: session.id,
                  provider: session.provider,
                  workingDirectory: session.workingDirectory,
                  firstSeen: session.firstSeen,
                  lastActive: session.lastActive,
                  outputTokens: session.sessionOutputTokens ?? 0,
                  turns: session.sessionTurns ?? 0,
                  stateSeconds: session.stateSeconds)
    }
}

/// Per-day aggregate over history records.
public struct HistoryRollup: Sendable {
    public let sessionCount: Int
    public let activeSeconds: Double   // time agents spent actually working
    public let outputTokens: Int
    public let turns: Int

    public static func compute(_ records: [HistoryRecord]) -> HistoryRollup {
        HistoryRollup(
            sessionCount: records.count,
            activeSeconds: records.reduce(0) { $0 + ($1.stateSeconds[SessionState.working.rawValue] ?? 0) },
            outputTokens: records.reduce(0) { $0 + $1.outputTokens },
            turns: records.reduce(0) { $0 + $1.turns }
        )
    }

    public init(sessionCount: Int, activeSeconds: Double, outputTokens: Int, turns: Int) {
        self.sessionCount = sessionCount
        self.activeSeconds = activeSeconds
        self.outputTokens = outputTokens
        self.turns = turns
    }
}
