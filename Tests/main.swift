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
    ("provider limits stored and replaced per provider", {
        let m = SessionManager()
        m.updateLimits(LimitsPayload(provider: .claude, limits: [
            ProviderLimit(kind: "session", percent: 16, resetsAtEpoch: 1_785_685_200),
            ProviderLimit(kind: "weekly_all", percent: 12),
        ]))
        m.updateLimits(LimitsPayload(provider: .codex, limits: [
            ProviderLimit(kind: "monthly", percent: 99),
        ]))
        expect(m.providerLimits[.claude]?.count == 2 && m.providerLimits[.codex]?.count == 1,
               "limits stored per provider")
        m.updateLimits(LimitsPayload(provider: .claude, limits: [
            ProviderLimit(kind: "session", percent: 20),
        ]))
        expect(m.providerLimits[.claude]?.count == 1 && m.providerLimits[.claude]?[0].percent == 20,
               "limits replaced on update")
        expect(m.providerLimits[.claude]?[0].shortLabel == "5h", "session maps to 5h label")
    }),
    ("stale-wait reminder fires once then resets on state change", {
        let m = SessionManager()
        let elevenMinAgo = (Date().timeIntervalSince1970 - 660) * 1000
        m.handleEvent(event(state: .waitingForInput, timestamp: elevenMinAgo))
        m.sendStaleWaitReminders()
        expect(m.sessions[0].reminded == true, "reminder marked after 10 min wait")
        m.sendStaleWaitReminders()
        expect(m.sessions[0].reminded == true, "no re-mark on second pass")
        m.handleEvent(event(state: .working, timestamp: elevenMinAgo + 1))
        expect(m.sessions[0].reminded == false, "reminded resets when state changes")
        m.handleEvent(event(state: .waitingForInput, timestamp: elevenMinAgo + 2))
        m.sendStaleWaitReminders()
        expect(m.sessions[0].reminded == true, "next stale wait reminds again")
    }),
    ("fresh wait does not remind", {
        let m = SessionManager()
        m.handleEvent(event(state: .waitingForInput, timestamp: Date().timeIntervalSince1970 * 1000))
        m.sendStaleWaitReminders()
        expect(m.sessions[0].reminded == false, "fresh wait not reminded")
    }),
    ("session ordering: needs-you first", {
        expect(MenuBarView.statePriority(.waitingForInput) < MenuBarView.statePriority(.error)
            && MenuBarView.statePriority(.error) < MenuBarView.statePriority(.working)
            && MenuBarView.statePriority(.working) < MenuBarView.statePriority(.idle),
            "waiting < error < working < idle")
    }),
    ("pace reserve math", {
        let now = Date()
        // 5h window, resets in 30 min → 90% elapsed; 30% used → +60 reserve
        let ahead = ProviderLimit(kind: "session", percent: 30,
                                  resetsAtEpoch: now.timeIntervalSince1970 + 1800)
        expect(ahead.paceReserve(now: now) == 60, "under pace yields +60 reserve")
        // 7d window, resets in 2d10h → ~65% elapsed; 80% used → ~-15 over
        let behind = ProviderLimit(kind: "weekly_all", percent: 80,
                                   resetsAtEpoch: now.timeIntervalSince1970 + 209_000)
        let r = behind.paceReserve(now: now) ?? 0
        expect(r <= -14 && r >= -16, "over pace yields ~-15")
        // Unknown window kind → nil
        let custom = ProviderLimit(kind: "mystery", percent: 50,
                                   resetsAtEpoch: now.timeIntervalSince1970 + 1000)
        expect(custom.paceReserve(now: now) == nil, "unknown window yields nil")
    }),
    ("history store: upsert, merge, rollup, prune", {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("shawk-history-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = HistoryStore(directory: tmp)
        let now = Date()
        let id = UUID()

        func record(_ id: UUID, firstSeen: Date, tokens: Int, working: Double) -> HistoryRecord {
            HistoryRecord(id: id, provider: .claude, workingDirectory: "/x/proj",
                          firstSeen: firstSeen, lastActive: firstSeen.addingTimeInterval(600),
                          outputTokens: tokens, turns: 5,
                          stateSeconds: [SessionState.working.rawValue: working])
        }

        // First snapshot, then an updated snapshot of the SAME session
        store.upsert([record(id, firstSeen: now, tokens: 100, working: 60)])
        store.upsert([record(id, firstSeen: now, tokens: 250, working: 120)])
        let today = store.records(day: HistoryStore.dayKey(now))
        expect(today.count == 1, "snapshot upsert merges by id, no duplicate")
        expect(today.first?.outputTokens == 250, "later snapshot wins")

        // A second session the same day → rollup math
        store.upsert([record(UUID(), firstSeen: now.addingTimeInterval(-3600), tokens: 50, working: 30)])
        let rollup = HistoryRollup.compute(store.records(day: HistoryStore.dayKey(now)))
        expect(rollup.sessionCount == 2 && rollup.outputTokens == 300 && rollup.activeSeconds == 150,
               "rollup sums sessions, tokens, working time")

        // Old day file → pruned; recent one survives
        let old = Calendar.current.date(byAdding: .day, value: -100, to: now)!
        store.upsert([record(UUID(), firstSeen: old, tokens: 1, working: 1)])
        expect(store.days(limit: 10).count == 2, "old day file written")
        store.prune(keepDays: 90, now: now)
        expect(store.records(day: HistoryStore.dayKey(old)).isEmpty, "90-day retention prunes old file")
        expect(!store.records(day: HistoryStore.dayKey(now)).isEmpty, "recent day survives prune")
    }),
    ("state time folds into buckets", {
        var s = AgentSession(pid: 1, provider: .claude, state: .working,
                             lastActive: Date(timeIntervalSince1970: 1000))
        s.foldStateTime(now: Date(timeIntervalSince1970: 1090))   // 90s working
        s.state = .waitingForInput
        s.foldStateTime(now: Date(timeIntervalSince1970: 1150))   // 60s waiting
        expect(s.stateSeconds[SessionState.working.rawValue] == 90, "working seconds folded")
        expect(s.stateSeconds[SessionState.waitingForInput.rawValue] == 60, "waiting seconds folded")
        s.foldStateTime(now: Date(timeIntervalSince1970: 1100))   // clock going backwards
        expect(s.stateSeconds[SessionState.waitingForInput.rawValue] == 60, "negative elapsed ignored")
    }),
    ("purged session lands in history", {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("shawk-history-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let m = SessionManager()
        m.historyStore = HistoryStore(directory: tmp)
        m.handleEvent(event(pid: 999_999, sessionOutputTokens: 4321, sessionTurns: 7))
        m.purgeInactiveSessions()   // pid 999999 is dead → ends the session
        let records = m.historyStore!.records(day: HistoryStore.dayKey(Date()))
        expect(records.count == 1 && records.first?.outputTokens == 4321,
               "ended session persisted with its totals")
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
