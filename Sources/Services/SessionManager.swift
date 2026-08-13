import Foundation
import Observation

public struct DailyStats: Codable, Sendable {
    public let outputTokens: Int
    public let turns: Int
}

@Observable
@MainActor
public final class SessionManager {
    public private(set) var sessions: [AgentSession] = []
    public private(set) var dailyStats: DailyStats?
    // Account-level usage limits per provider (Claude 5h/weekly, Codex windows)
    public private(set) var providerLimits: [AgentProvider: [ProviderLimit]] = [:]
    // Local session history (nil in tests that don't exercise persistence)
    public var historyStore: HistoryStore?
    private var lastHistorySnapshot = Date.distantPast

    public func updateDaily(_ stats: DailyStats) {
        dailyStats = stats
    }

    public func updateLimits(_ payload: LimitsPayload) {
        providerLimits[payload.provider] = payload.limits
    }
    
    public init() {
        // Start a periodic cleanup timer for dead/inactive PIDs
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeInactiveSessions()
                self?.sendStaleWaitReminders()
                self?.snapshotHistoryIfDue()
            }
        }
    }
    
    public func handleEvent(_ payload: EventPayload) {
        let now = Date()
        
        let tokenUsage: TokenUsage?
        if let input = payload.inputTokens, let output = payload.outputTokens, let limit = payload.totalLimit {
            tokenUsage = TokenUsage(inputTokens: input, outputTokens: output, totalLimit: limit)
        } else {
            tokenUsage = nil
        }
        
        if let index = sessions.firstIndex(where: { $0.pid == payload.pid }) {
            let previousState = sessions[index].state
            
            // Update existing session; a nil state is a heartbeat that must
            // not override precise state reported by agent hooks
            sessions[index].provider = payload.provider
            var stateApplied = false
            if let newState = payload.state {
                // Hooks run async and can deliver out of order at turn
                // boundaries — drop a timestamped state older than the last
                // applied one (e.g. a stale Stop arriving after the next
                // turn's UserPromptSubmit).
                let isStale: Bool
                if let ts = payload.timestamp, let lastTs = sessions[index].stateTimestamp {
                    isStale = ts < lastTs
                } else {
                    isStale = false
                }
                if !isStale {
                    if newState != sessions[index].state {
                        sessions[index].reminded = false
                        sessions[index].foldStateTime(now: now)
                    }
                    sessions[index].state = newState
                    if let ts = payload.timestamp {
                        sessions[index].stateTimestamp = ts
                    }
                    stateApplied = true
                }
            }
            if let tokenUsage = tokenUsage {
                sessions[index].tokenUsage = tokenUsage
            }
            if let title = payload.terminalTitle {
                sessions[index].terminalTitle = title
            }
            if let dir = payload.workingDirectory {
                sessions[index].workingDirectory = dir
            }
            if let cmd = payload.commandLine {
                sessions[index].commandLine = cmd
            }
            if let out = payload.sessionOutputTokens {
                sessions[index].sessionOutputTokens = out
            }
            if let turns = payload.sessionTurns {
                sessions[index].sessionTurns = turns
            }
            sessions[index].lastActive = now
            
            // Send notification only if transition is to waitingForInput
            if stateApplied && previousState != .waitingForInput && payload.state == .waitingForInput {
                NotificationManager.shared.sendAlert(for: sessions[index])
            }
        } else {
            // Register new session
            var newSession = AgentSession(
                pid: payload.pid,
                provider: payload.provider,
                state: payload.state ?? .idle,
                tokenUsage: tokenUsage,
                terminalTitle: payload.terminalTitle,
                lastActive: now,
                workingDirectory: payload.workingDirectory,
                commandLine: payload.commandLine
            )
            if payload.state != nil {
                newSession.stateTimestamp = payload.timestamp
            }
            newSession.sessionOutputTokens = payload.sessionOutputTokens
            newSession.sessionTurns = payload.sessionTurns
            sessions.append(newSession)
            
            if payload.state == .waitingForInput {
                NotificationManager.shared.sendAlert(for: newSession)
            }
        }
    }
    
    // Sessions stuck in waitingForInput for 10+ minutes get one reminder —
    // the original alert is easy to miss when you're deep in another session.
    static let reminderAfterMs: Double = 600_000

    public func sendStaleWaitReminders(now: Date = Date()) {
        for index in sessions.indices {
            guard sessions[index].state == .waitingForInput,
                  !sessions[index].reminded,
                  let ts = sessions[index].stateTimestamp,
                  now.timeIntervalSince1970 * 1000 - ts > Self.reminderAfterMs else { continue }
            sessions[index].reminded = true
            NotificationManager.shared.sendStaleReminder(for: sessions[index])
        }
    }

    public func purgeInactiveSessions() {
        // Purge sessions where the process is no longer running (kill -0 fails)
        // or hasn't checked in for over 5 minutes (300 seconds)
        let now = Date()
        var ended: [HistoryRecord] = []
        sessions.removeAll { session in
            // Check if process exists using kill(pid, 0)
            let isRunning = kill(session.pid, 0) == 0
            let isExpired = now.timeIntervalSince(session.lastActive) > 300.0

            // If process is dead or inactive for too long, purge it
            if !isRunning || isExpired {
                var final = session
                // Count trailing time only up to when the session was last
                // heard from — not up to the purge that noticed it was gone
                final.foldStateTime(now: max(session.lastActive, session.stateChangedAt))
                ended.append(HistoryRecord(from: final))
                return true
            }
            return false
        }
        if !ended.isEmpty {
            historyStore?.upsert(ended)
        }
    }

    // Snapshot live sessions to history every minute — bounds data loss on
    // quit/crash to ≤60s without writing on every 10s timer tick.
    static let historySnapshotInterval: TimeInterval = 60

    public func snapshotHistoryIfDue(now: Date = Date()) {
        guard let store = historyStore,
              now.timeIntervalSince(lastHistorySnapshot) >= Self.historySnapshotInterval else { return }
        lastHistorySnapshot = now
        guard !sessions.isEmpty else { return }
        for index in sessions.indices {
            sessions[index].foldStateTime(now: now)
        }
        store.upsert(sessions.map { HistoryRecord(from: $0) })
    }
    
    public func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }
}
