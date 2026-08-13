import SwiftUI
import SessionHawkCore

@main
struct SessionHawkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager: SessionManager
    @State private var updateChecker: UpdateChecker
    private let hookListener: HookListener

    init() {
        // Start the IPC listener at launch — waiting for the menu bar popover
        // to appear would leave port 9422 closed until the user clicks the icon.
        let manager = MainActor.assumeIsolated { SessionManager() }
        _sessionManager = State(initialValue: manager)
        MainActor.assumeIsolated {
            let store = HistoryStore()
            store.prune()   // retention enforced once per launch
            manager.historyStore = store
        }
        hookListener = HookListener(sessionManager: manager)
        hookListener.start()
        let checker = MainActor.assumeIsolated { UpdateChecker() }
        _updateChecker = State(initialValue: checker)
        MainActor.assumeIsolated { checker.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager, updateChecker: updateChecker)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }
    
    // Template image so the system recolors it for light/dark menu bars
    static let menuBarHawk: NSImage? = {
        guard let url = Bundle.main.url(forResource: "menubar-hawk", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    @ViewBuilder
    private var menuBarLabel: some View {
        let sessions = sessionManager.sessions
        let waitingCount = sessions.filter { $0.state == .waitingForInput }.count
        let workingCount = sessions.filter { $0.state == .working }.count
        
        HStack(spacing: 3) {
            if let hawk = Self.menuBarHawk {
                Image(nsImage: hawk)
            } else {
                Image(systemName: "bird.fill")
            }
            if waitingCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .symbolEffect(.pulse, options: .repeating)
                Text("\(waitingCount)")
                    .font(.caption.bold())
            } else if workingCount > 0 {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}
