// Plain-executable test runner (no XCTest — unavailable with CLT-only
// toolchains). Run with: swift run SessionHawkTests
import Foundation
import SessionHawkCore

setenv("SESSIONHAWK_NO_NOTIFY", "1", 1)

var failures = 0
var passed = 0

func expect(_ condition: Bool, _ name: String,
            file: StaticString = #file, line: UInt = #line) {
    if condition {
        passed += 1
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name)  (\(file):\(line))")
    }
}

func event(pid: Int32 = 4242,
           provider: AgentProvider = .claude,
           state: SessionState? = nil,
           inputTokens: Int? = nil,
           outputTokens: Int? = nil,
           totalLimit: Int? = nil,
           sessionOutputTokens: Int? = nil,
           sessionTurns: Int? = nil,
           timestamp: Double? = nil) -> EventPayload {
    EventPayload(pid: pid, provider: provider, state: state,
                 inputTokens: inputTokens, outputTokens: outputTokens,
                 totalLimit: totalLimit,
                 sessionOutputTokens: sessionOutputTokens,
                 sessionTurns: sessionTurns,
                 timestamp: timestamp)
}

let tests: [(String, @MainActor () -> Void)] = [
    ("new session defaults to idle", {
        let m = SessionManager()
        m.handleEvent(event())
        expect(m.sessions.count == 1 && m.sessions[0].state == .idle,
               "new session defaults to idle")
    }),
    ("heartbeat does not override hook state", {
        let m = SessionManager()
        m.handleEvent(event(state: .waitingForInput, timestamp: 1000))
        m.handleEvent(event(state: nil, inputTokens: 50_000, outputTokens: 200, totalLimit: 200_000))
        expect(m.sessions[0].state == .waitingForInput, "heartbeat preserves hook state")
        expect(m.sessions[0].tokenUsage?.inputTokens == 50_000, "heartbeat still refreshes tokens")
    }),
    ("stale timestamped state is dropped", {
        let m = SessionManager()
        m.handleEvent(event(state: .working, timestamp: 2000))
        m.handleEvent(event(state: .waitingForInput, timestamp: 1500))   // late Stop
        expect(m.sessions[0].state == .working, "stale state dropped")
        expect(m.sessions[0].stateTimestamp == 2000, "timestamp unchanged after stale drop")
    }),
    ("newer timestamped state is applied", {
        let m = SessionManager()
        m.handleEvent(event(state: .working, timestamp: 1000))
        m.handleEvent(event(state: .waitingForInput, timestamp: 2000))
        expect(m.sessions[0].state == .waitingForInput, "newer state applied")
    }),
    ("untimestamped state always applies", {
        let m = SessionManager()
        m.handleEvent(event(state: .working, timestamp: 2000))
        m.handleEvent(event(state: .idle))   // feeder reconciliation, no timestamp
        expect(m.sessions[0].state == .idle, "untimestamped feeder state applies")
    }),
    ("session totals update and persist across heartbeats", {
        let m = SessionManager()
        m.handleEvent(event(sessionOutputTokens: 1000, sessionTurns: 10))
        m.handleEvent(event())   // totals-free heartbeat must not erase them
        expect(m.sessions[0].sessionOutputTokens == 1000 && m.sessions[0].sessionTurns == 10,
               "totals survive totals-free heartbeat")
        m.handleEvent(event(sessionOutputTokens: 2000, sessionTurns: 22))
        expect(m.sessions[0].sessionOutputTokens == 2000 && m.sessions[0].sessionTurns == 22,
               "totals update")
    }),
    ("partial token payload yields no usage", {
        let m = SessionManager()
        m.handleEvent(event(inputTokens: 100))
        expect(m.sessions[0].tokenUsage == nil, "partial tokens ignored")
    }),
    ("purge removes dead pid", {
        let m = SessionManager()
        m.handleEvent(event(pid: 999_999))
        m.purgeInactiveSessions()
        expect(m.sessions.isEmpty, "dead pid purged")
    }),
    ("purge keeps live recent session", {
        let m = SessionManager()
        m.handleEvent(event(pid: ProcessInfo.processInfo.processIdentifier))
        m.purgeInactiveSessions()
        expect(m.sessions.count == 1, "live session kept")
    }),
    ("usage percentage", {
        let usage = TokenUsage(inputTokens: 150_000, outputTokens: 10_000, totalLimit: 200_000)
        expect(abs(usage.usagePercentage - 80.0) < 0.001, "80% usage computed")
        let empty = TokenUsage(inputTokens: 0, outputTokens: 0, totalLimit: 0)
        expect(empty.usagePercentage == 0.0, "zero limit yields 0%")
    }),
]

for (_, test) in tests {
    await MainActor.run { test() }
}

print("\n\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
