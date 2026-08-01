import AppKit
import SessionHawkCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission on launch
        NotificationManager.shared.requestAuthorization()
        
        // Make the app run as an accessory (pure menu bar app, no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }
}
