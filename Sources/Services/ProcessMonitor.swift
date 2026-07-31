import Foundation
import AppKit

public final class ProcessMonitor: Sendable {
    public init() {}
    
    /// Checks if a PID is alive.
    public func isProcessRunning(pid: Int32) -> Bool {
        return kill(pid, 0) == 0
    }
    
    /// Retrieves the process name for a given PID.
    public func getProcessName(pid: Int32) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.localizedName
        }
        
        // Fallback to running `ps -p <pid> -o comm=`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "comm="]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Silence stderr
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return URL(fileURLWithPath: trimmed).lastPathComponent
                }
            }
        } catch {
            print("Failed to run ps for process name: \(error)")
        }
        
        return nil
    }
}
