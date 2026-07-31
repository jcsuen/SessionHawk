import SwiftUI

public struct MenuBarView: View {
    var sessionManager: SessionManager
    @State private var selectedSession: AgentSession? = nil
    // MenuBarExtra windows cannot be drag-resized on macOS, so the size is a
    // persisted preference instead.
    @AppStorage("windowSize") private var windowSize: String = WindowSize.medium.rawValue

    enum WindowSize: String, CaseIterable {
        case small = "S"
        case medium = "M"
        case large = "L"

        var width: CGFloat {
            switch self {
            case .small: return 320
            case .medium: return 380
            case .large: return 440
            }
        }

        var listHeight: CGFloat {
            switch self {
            case .small: return 300
            case .medium: return 480
            case .large: return 700
            }
        }
    }

    private var size: WindowSize { WindowSize(rawValue: windowSize) ?? .medium }

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if let selected = selectedSession, let session = sessionManager.sessions.first(where: { $0.id == selected.id }) {
                DetailPopover(
                    session: session,
                    onFocus: {
                        TerminalFocusHelper.focusTerminal(forPid: session.pid)
                    },
                    onDismiss: {
                        selectedSession = nil
                    }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            } else {
                HStack {
                    Text("SessionHawk")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text("\(sessionManager.sessions.count) active session\(sessionManager.sessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if sessionManager.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "eyes")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No active agent sessions")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("Run sessionhawk-hook.sh in your terminal to monitor sessions.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(height: 180)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(sessionManager.sessions) { session in
                                SessionRowView(
                                    session: session,
                                    onFocus: {
                                        selectedSession = session
                                    }
                                )
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: size.listHeight)
                }
                
                Divider()
                
                HStack {
                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        Label("Quit", systemImage: "power")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/jcsuen")!)
                    } label: {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Enjoying SessionHawk? Buy me a coffee ☕")

                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/jcsuen/SessionHawk")!)
                    } label: {
                        Image(systemName: "star")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("SessionHawk on GitHub — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")

                    Spacer()

                    Picker("", selection: $windowSize) {
                        ForEach(WindowSize.allCases, id: \.rawValue) { s in
                            Text(s.rawValue).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .help("Window size")
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: size.width)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedSession?.id)
    }
}
