// gen-demo-gif.swift — renders the "needs you" flow with synthetic data into
// an animated GIF for the landing page / README. All data is fake by design:
// public assets must never show real paths or session names.
// Build: swiftc -parse-as-library scripts/gen-demo-gif.swift Sources/Models/AgentSession.swift Sources/Views/SessionRowView.swift -o <out>
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct DemoGifGen {
@MainActor
static func main() {

func session(_ pid: Int32, _ provider: AgentProvider, _ state: SessionState,
             _ dir: String, _ input: Int) -> AgentSession {
    AgentSession(pid: pid, provider: provider, state: state,
                 tokenUsage: TokenUsage(inputTokens: input, outputTokens: 1_100, totalLimit: 1_000_000),
                 workingDirectory: dir)
}

let api = "/Users/dev/projects/api-server"
let web = "/Users/dev/projects/web-app"
let etl = "/Users/dev/projects/data-pipeline"

// The story: three agents grinding → one stops and needs you → it jumps to
// the top with an amber badge → you answer, it goes back to work.
let frames: [(sessions: [AgentSession], caption: String, delay: Double)] = [
    ([session(48231, .claude, .working, api, 279_450),
      session(51876, .claude, .working, web, 168_562),
      session(40112, .gemini, .working, etl, 48_040)],
     "3 agents working — you're free to think", 1.6),
    ([session(48231, .claude, .working, api, 291_780),
      session(51876, .claude, .working, web, 174_210),
      session(40112, .gemini, .working, etl, 52_395)],
     "3 agents working — you're free to think", 1.2),
    ([session(51876, .claude, .waitingForInput, web, 175_030),
      session(48231, .claude, .working, api, 302_115),
      session(40112, .gemini, .working, etl, 55_871)],
     "web-app needs you → jumps to the top + pings you", 2.6),
    ([session(51876, .claude, .working, web, 176_940),
      session(48231, .claude, .working, api, 313_402),
      session(40112, .gemini, .working, etl, 60_118)],
     "answered — back to work in one click", 2.0),
]

func render(_ sessions: [AgentSession], _ caption: String) -> NSImage {
    let header = HStack {
        VStack(alignment: .leading, spacing: 1) {
            Text("SessionHawk").font(.headline).fontWeight(.bold)
            Text("Today: 1.2M tokens · 981 turns")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Claude Code").foregroundStyle(.secondary)
                Text("5h 21%")
                Text("↻2h10m").foregroundStyle(.tertiary)
                Text("wk 12%")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(sessions.count) active sessions")
            .font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
    }
    .padding()

    let content = VStack(spacing: 0) {
        header
        Divider().padding(.bottom, 10)
        VStack(spacing: 8) {
            ForEach(sessions) { s in SessionRowView(session: s, onFocus: {}) }
        }
        .padding(.horizontal)
        Text(caption)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
    .frame(width: 380)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let img = renderer.nsImage else { fatalError("render failed") }
    return img
}

NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

let out = URL(fileURLWithPath: "docs/screenshots/needs-you-demo.gif")
try! FileManager.default.createDirectory(atPath: "docs/screenshots", withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString,
                                                 frames.count, nil) else { fatalError("gif dest failed") }
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [
    kCGImagePropertyGIFLoopCount: 0   // loop forever
]] as CFDictionary)

for frame in frames {
    let img = render(frame.sessions, frame.caption)
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("cg failed") }
    CGImageDestinationAddImage(dest, cg, [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: frame.delay
    ]] as CFDictionary)
}
guard CGImageDestinationFinalize(dest) else { fatalError("gif finalize failed") }
print("wrote \(out.path)")

}
}
