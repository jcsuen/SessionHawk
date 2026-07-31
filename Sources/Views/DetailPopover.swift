import SwiftUI

public struct DetailPopover: View {
    let session: AgentSession
    let onFocus: () -> Void
    let onDismiss: () -> Void
    
    public init(session: AgentSession, onFocus: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.session = session
        self.onFocus = onFocus
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.provider.displayName)
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            Group {
                DetailRow(label: "Status", value: session.state.displayName)
                DetailRow(label: "Process ID", value: "\(session.pid)")
                
                if let dir = session.workingDirectory {
                    DetailRow(label: "Working Dir", value: dir, isCode: true)
                }
                
                if let cmd = session.commandLine {
                    DetailRow(label: "Command", value: cmd, isCode: true)
                }
                
                DetailRow(label: "Last Active", value: formattedDate(session.lastActive))
            }
            
            if let tokenUsage = session.tokenUsage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Token Usage Breakdown")
                        .font(.headline)
                        .padding(.top, 4)
                    
                    HStack {
                        Text("Input:")
                        Spacer()
                        Text("\(tokenUsage.inputTokens)").monospaced()
                    }
                    HStack {
                        Text("Output:")
                        Spacer()
                        Text("\(tokenUsage.outputTokens)").monospaced()
                    }
                    HStack {
                        Text("Total Limit:")
                        Spacer()
                        Text("\(tokenUsage.totalLimit)").monospaced()
                    }
                    
                    ProgressView(value: min(tokenUsage.usagePercentage, 100), total: 100)
                        .tint(tokenUsage.usagePercentage > 80 ? .red : .accentColor)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor).opacity(0.1))
                .cornerRadius(6)
            }
            
            HStack(spacing: 12) {
                Button(action: onFocus) {
                    Label("Focus Terminal", systemImage: "terminal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button(role: .destructive, action: killProcess) {
                    Label("Kill Process", systemImage: "xmark.octagon.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func killProcess() {
        kill(session.pid, SIGKILL)
        onDismiss()
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isCode: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(isCode ? .system(.body, design: .monospaced) : .body)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}
