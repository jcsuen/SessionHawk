import Foundation

/// One usage-limit gauge for a provider account (e.g. Claude's 5-hour session
/// window or Codex's monthly window). `resetsAtEpoch` is Unix seconds so shell
/// feeders can send it without date-format negotiation.
public struct ProviderLimit: Codable, Sendable, Identifiable {
    public let kind: String       // "session" | "weekly_all" | "weekly_scoped" | "monthly" | ...
    public let percent: Double
    public let resetsAtEpoch: Double?

    public var id: String { kind }

    public var resetsAt: Date? {
        resetsAtEpoch.map { Date(timeIntervalSince1970: $0) }
    }

    /// Short gauge label: "5h", "wk", "mo"...
    public var shortLabel: String {
        switch kind {
        case "session": return "5h"
        case "weekly_all": return "wk"
        case "weekly_scoped": return "model wk"
        case "monthly": return "mo"
        default: return kind
        }
    }

    /// Length of this limit's rolling window, when derivable from its kind.
    public var windowSeconds: Double? {
        switch kind {
        case "session": return 5 * 3600
        case "weekly_all", "weekly_scoped": return 7 * 86400
        case "monthly": return 30 * 86400
        default: return nil
        }
    }

    /// Pace vs a steady burn through the window: positive = percentage points
    /// in reserve, negative = points ahead of pace (headed for the limit).
    public func paceReserve(now: Date = Date()) -> Int? {
        guard let window = windowSeconds, let reset = resetsAt else { return nil }
        let elapsed = window - reset.timeIntervalSince(now)
        guard elapsed > 0, elapsed <= window else { return nil }
        let expected = elapsed / window * 100
        return Int((expected - percent).rounded())
    }

    public init(kind: String, percent: Double, resetsAtEpoch: Double? = nil) {
        self.kind = kind
        self.percent = percent
        self.resetsAtEpoch = resetsAtEpoch
    }
}

public struct LimitsPayload: Codable, Sendable {
    public let provider: AgentProvider
    public let limits: [ProviderLimit]

    public init(provider: AgentProvider, limits: [ProviderLimit]) {
        self.provider = provider
        self.limits = limits
    }
}
