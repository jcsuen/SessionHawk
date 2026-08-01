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

    public func updateDaily(_ stats: DailyStats) {
        dailyStats = stats
    }
    
    public init() {
        // Start a periodic cleanup timer for dead/inactive PIDs
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeInactiveSessions()
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
    
    public func purgeInactiveSessions() {
        // Purge sessions where the process is no longer running (kill -0 fails)
        // or hasn't checked in for over 5 minutes (300 seconds)
        let now = Date()
        sessions.removeAll { session in
            // Check if process exists using kill(pid, 0)
            let isRunning = kill(session.pid, 0) == 0
            let isExpired = now.timeIntervalSince(session.lastActive) > 300.0
            
            // If process is dead or inactive for too long, purge it
            return !isRunning || isExpired
        }
    }
    
    public func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }
}
