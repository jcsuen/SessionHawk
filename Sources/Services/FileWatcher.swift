import Foundation

public final class FileWatcher: Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "com.sessionhawk.filewatcher")
    
    private final class State {
        var fileDescriptor: Int32 = -1
        var dispatchSource: DispatchSourceFileSystemObject?
    }
    private let state = State()
    private let stateLock = NSLock()
    
    public var onChange: (@Sendable () -> Void)?
    
    public init(path: String, onChange: (@Sendable () -> Void)? = nil) {
        self.path = path
        self.onChange = onChange
    }
    
    public func start() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("FileWatcher failed to open path: \(path)")
            return
        }
        
        state.fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            self?.onChange?()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        state.dispatchSource = source
        source.resume()
    }
    
    public func stop() {
        stateLock.lock()
        state.dispatchSource?.cancel()
        state.dispatchSource = nil
        state.fileDescriptor = -1
        stateLock.unlock()
    }
}
