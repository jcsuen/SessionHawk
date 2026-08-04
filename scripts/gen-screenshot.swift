// gen-screenshot.swift — renders the session list UI with sample data to
// docs/screenshots/sessions.png for the README.
// Build: swiftc scripts/gen-screenshot.swift Sources/Models/AgentSession.swift Sources/Views/SessionRowView.swift -o <out>
import SwiftUI
import AppKit

@main
struct ScreenshotGen {
@MainActor
static func main() {

let sessions = [
    AgentSession(
        pid: 48231, provider: .claude, state: .working,
        tokenUsage: TokenUsage(inputTokens: 279_450, outputTokens: 1_204, totalLimit: 1_000_000),
        workingDirectory: "/Users/dev/projects/api-server"
    ),
    AgentSession(
        pid: 51876, provider: .claude, state: .waitingForInput,
        tokenUsage: TokenUsage(inputTokens: 168_562, outputTokens: 892, totalLimit: 1_000_000),
        workingDirectory: "/Users/dev/projects/web-app"
    ),
    AgentSession(
        pid: 40112, provider: .gemini, state: .idle,
        tokenUsage: TokenUsage(inputTokens: 48_040, outputTokens: 938, totalLimit: 1_000_000),
        workingDirectory: "/Users/dev/projects/data-pipeline"
    ),
]

let header = HStack {
    VStack(alignment: .leading, spacing: 1) {
        Text("SessionHawk")
            .font(.headline)
            .fontWeight(.bold)
        Text("Today: 1.2M tokens · 981 turns")
            .font(.caption2)
            .foregroundStyle(.secondary)
        HStack(spacing: 4) {
            Text("Claude Code").foregroundStyle(.secondary)
            Text("5h 21%")
            Text("↻2h10m").foregroundStyle(.tertiary)
            Text("wk 12%")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    Spacer()
    Text("\(sessions.count) active sessions")
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(4)
}
.padding()

let list = VStack(spacing: 8) {
    ForEach(sessions) { session in
        SessionRowView(session: session, onFocus: {})
    }
}
.padding([.horizontal, .bottom])

let content = VStack(spacing: 0) {
    header
    Divider().padding(.bottom, 10)
    list
}
.frame(width: 380)
.background(Color(nsColor: .windowBackgroundColor))
.environment(\.colorScheme, .dark)

NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
let renderer = ImageRenderer(content: content)
renderer.scale = 2

guard let nsImage = renderer.nsImage,
      let tiff = nsImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! FileManager.default.createDirectory(atPath: "docs/screenshots", withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: "docs/screenshots/sessions.png"))
print("wrote docs/screenshots/sessions.png")

}
}
