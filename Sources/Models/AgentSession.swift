import Foundation

public struct TokenUsage: Codable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalLimit: Int
    
    public var usagePercentage: Double {
        guard totalLimit > 0 else { return 0.0 }
        return Double(inputTokens + outputTokens) / Double(totalLimit) * 100.0
    }
    
    public init(inputTokens: Int, outputTokens: Int, totalLimit: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalLimit = totalLimit
    }
}

public enum AgentProvider: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
    case gemini
    case cursor
    case custom
    
    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "OpenAI Codex"
        case .gemini: return "Gemini CLI"
        case .cursor: return "Cursor"
        case .custom: return "Custom Agent"
        }
    }
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case waitingForInput
    case working
    case error
    case idle
    
    public var displayName: String {
        switch self {
        case .waitingForInput: return "Waiting for Input"
        case .working: return "Working"
        case .error: return "Error"
        case .idle: return "Idle"
        }
    }
}

public struct AgentSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let pid: Int32
    public var provider: AgentProvider
    public var state: SessionState
    public var tokenUsage: TokenUsage?
    public var terminalTitle: String?
    public var lastActive: Date
    public var workingDirectory: String?
    public var commandLine: String?
    // ms-epoch of the last applied timestamped state change (hook events);
    // used to drop out-of-order async hook deliveries
    public var stateTimestamp: Double?

    public init(id: UUID = UUID(),
                pid: Int32,
                provider: AgentProvider,
                state: SessionState,
                tokenUsage: TokenUsage? = nil,
                terminalTitle: String? = nil,
                lastActive: Date = Date(),
                workingDirectory: String? = nil,
                commandLine: String? = nil) {
        self.id = id
        self.pid = pid
        self.provider = provider
        self.state = state
        self.tokenUsage = tokenUsage
        self.terminalTitle = terminalTitle
        self.lastActive = lastActive
        self.workingDirectory = workingDirectory
        self.commandLine = commandLine
    }
}
