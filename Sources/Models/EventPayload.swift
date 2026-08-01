import Foundation

public struct EventPayload: Codable, Sendable {
    public let pid: Int32
    public let provider: AgentProvider
    // nil = heartbeat: refreshes lastActive/tokens without overriding
    // precise state reported by agent hooks
    public let state: SessionState?
    public let terminalTitle: String?
    public let workingDirectory: String?
    public let commandLine: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalLimit: Int?
    // Cumulative session totals parsed from the transcript by the feeder
    public let sessionOutputTokens: Int?
    public let sessionTurns: Int?
    // Event time in ms since epoch. Hooks run async and can deliver out of
    // order at turn boundaries; stale state changes are discarded by comparing
    // this against the session's last applied state timestamp.
    public let timestamp: Double?
    
    public init(pid: Int32,
                provider: AgentProvider,
                state: SessionState?,
                terminalTitle: String? = nil,
                workingDirectory: String? = nil,
                commandLine: String? = nil,
                inputTokens: Int? = nil,
                outputTokens: Int? = nil,
                totalLimit: Int? = nil,
                sessionOutputTokens: Int? = nil,
                sessionTurns: Int? = nil,
                timestamp: Double? = nil) {
        self.pid = pid
        self.provider = provider
        self.state = state
        self.terminalTitle = terminalTitle
        self.workingDirectory = workingDirectory
        self.commandLine = commandLine
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalLimit = totalLimit
        self.sessionOutputTokens = sessionOutputTokens
        self.sessionTurns = sessionTurns
        self.timestamp = timestamp
    }
}
