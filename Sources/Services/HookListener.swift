import Foundation
import Network

public final class HookListener: Sendable {
    private let port: NWEndpoint.Port = 9422
    private let sessionManager: SessionManager
    private let queue = DispatchQueue(label: "com.sessionhawk.listener")
    
    // Using a locked reference wrapper or class wrapper because NWListener is not Sendable in some contexts
    private final class ListenerWrapper {
        var listener: NWListener?
    }
    private let wrapper = ListenerWrapper()
    private let wrapperLock = NSLock()
    
    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }
    
    public func start() {
        do {
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters, on: port)
            
            wrapperLock.lock()
            wrapper.listener = listener
            wrapperLock.unlock()
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("HookListener started on port 9422")
                case .failed(let error):
                    print("HookListener failed with error: \(error)")
                case .cancelled:
                    print("HookListener cancelled")
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener.start(queue: queue)
        } catch {
            print("Failed to initialize HookListener: \(error)")
        }
    }
    
    public func stop() {
        wrapperLock.lock()
        wrapper.listener?.cancel()
        wrapper.listener = nil
        wrapperLock.unlock()
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection)
    }
    
    private func readRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Connection error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                self.processData(data, connection: connection)
            } else if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func processData(_ data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let bodySeparator: String
        if requestString.contains("\r\n\r\n") {
            bodySeparator = "\r\n\r\n"
        } else if requestString.contains("\n\n") {
            bodySeparator = "\n\n"
        } else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let components = requestString.components(separatedBy: bodySeparator)
        guard components.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let headersPart = components[0]
        let bodyPart = components.dropFirst().joined(separator: bodySeparator)
        
        let lines = headersPart.components(separatedBy: .newlines)
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let reqParts = firstLine.split(separator: " ")
        guard reqParts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let method = reqParts[0]
        let path = reqParts[1]
        
        if method == "GET" && path == "/v1/sessions" {
            let manager = sessionManager
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let body = (try? encoder.encode(manager.sessions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                self.sendResponse(connection: connection, statusCode: 200, body: body)
            }
        } else if method == "POST" && path == "/v1/event" {
            guard let jsonData = bodyPart.data(using: .utf8) else {
                sendResponse(connection: connection, statusCode: 400, body: "Invalid UTF-8 Body")
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let payload = try decoder.decode(EventPayload.self, from: jsonData)
                
                Task { @MainActor in
                    self.sessionManager.handleEvent(payload)
                }
                
                sendResponse(connection: connection, statusCode: 200, body: "{\"status\":\"ok\"}")
            } catch {
                print("Error decoding payload: \(error)")
                sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"\(error.localizedDescription)\"}")
            }
        } else {
            sendResponse(connection: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusPhrase: String
        switch statusCode {
        case 200: statusPhrase = "OK"
        case 400: statusPhrase = "Bad Request"
        case 404: statusPhrase = "Not Found"
        default: statusPhrase = "Internal Server Error"
        }
        
        let responseString = "HTTP/1.1 \(statusCode) \(statusPhrase)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.utf8.count)\r\n" +
            "Connection: close\r\n\r\n" +
            body
        
        guard let responseData = responseString.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
