import Foundation
import UserNotifications
import AppKit

public struct TerminalFocusHelper {
    /// Focus the exact terminal tab hosting the given process, by resolving
    /// its controlling TTY and matching it against iTerm2 sessions or
    /// Terminal.app tabs. Falls back to activating the frontmost terminal app.
    public static func focusTerminal(forPid pid: Int32) {
        guard let tty = ttyPath(forPid: pid) else {
            activateAnyTerminal()
            return
        }

        let iTermRunning = isRunning(bundleId: "com.googlecode.iterm2")
        let terminalRunning = isRunning(bundleId: "com.apple.Terminal")

        var script = ""
        if iTermRunning {
            script += """
            tell application "iTerm"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell

            """
        }
        if terminalRunning {
            script += """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }

        guard !script.isEmpty else {
            activateAnyTerminal()
            return
        }

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
            activateAnyTerminal()
        }
    }

    /// Controlling terminal of a process, e.g. "/dev/ttys003", via `ps -o tty=`.
    private static func ttyPath(forPid pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let tty = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !tty.isEmpty, tty != "??" else {
            return nil
        }
        return "/dev/\(tty)"
    }

    private static func isRunning(bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private static func activateAnyTerminal() {
        for bundleId in ["com.googlecode.iterm2", "com.apple.Terminal"] {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate()
                return
            }
        }
    }
}

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, Sendable {
    public static let shared = NotificationManager()

    // UNUserNotificationCenter aborts the process when the executable is not
    // inside a .app bundle (e.g. `swift run` during development), so fall back
    // to osascript notifications in that case.
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    private override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    public func requestAuthorization() {
        guard hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    // Follow-up when a waitingForInput session has been ignored for a while.
    public func sendStaleReminder(for session: AgentSession) {
        guard getenv("SESSIONHAWK_NO_NOTIFY") == nil else { return }
        let title = "Still waiting on you"
        let body = "\(session.provider.displayName) (\(session.terminalTitle ?? "PID \(session.pid)")) has been waiting 10+ minutes."
        guard hasBundle else {
            let esc = body.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "display notification \"\(esc)\" with title \"\(title)\""
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.userInfo = ["pid": Int(session.pid), "terminalTitle": session.terminalTitle ?? ""]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "sessionhawk-remind-\(session.pid)", content: content, trigger: nil)
        ) { _ in }
    }

    public func sendAlert(for session: AgentSession) {
        // Kill-switch for test runs and headless environments (getenv, not
        // ProcessInfo: tests set it after launch via setenv).
        guard getenv("SESSIONHAWK_NO_NOTIFY") == nil else { return }
        guard hasBundle else {
            sendFallbackAlert(for: session)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Agent Waiting for Input"
        content.body = "\(session.provider.displayName) (PID \(session.pid)) is waiting for your input."
        content.sound = UNNotificationSound.default
        content.userInfo = [
            "pid": Int(session.pid),
            "terminalTitle": session.terminalTitle ?? ""
        ]
        
        let request = UNNotificationRequest(
            identifier: "sessionhawk-waiting-\(session.pid)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification: \(error)")
            }
        }
    }
    
    private func sendFallbackAlert(for session: AgentSession) {
        let body = "\(session.provider.displayName) (PID \(session.pid)) is waiting for your input."
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(body)\" with title \"Agent Waiting for Input\" sound name \"default\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let pid = userInfo["pid"] as? Int {
            TerminalFocusHelper.focusTerminal(forPid: Int32(pid))
        }
        completionHandler()
    }
}
