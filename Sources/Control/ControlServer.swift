import AppKit
import Foundation
import Network
import Security

/// Loopback HTTP API for `scripts/kterm`. Binds 127.0.0.1 and requires the
/// bearer token written to `~/Library/Application Support/kterm/endpoint.json`
/// (mode 600).
@MainActor
final class ControlServer {
    static let shared = ControlServer()

    private var listener: NWListener?
    private var token = ""
    private var starting = false

    private init() {}

    func start() {
        guard listener == nil, !starting else { return }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        starting = true
        attempt(remaining: 20)
    }

    private func attempt(remaining: Int) {
        guard remaining > 0 else {
            starting = false
            NSLog("kterm: control server failed to bind")
            return
        }
        let candidate = UInt16.random(in: 49152...65535)
        guard let port = NWEndpoint.Port(rawValue: candidate),
              let address = IPv4Address("127.0.0.1")
        else {
            attempt(remaining: remaining - 1)
            return
        }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(address), port: port)
        guard let listener = try? NWListener(using: params) else {
            attempt(remaining: remaining - 1)
            return
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Task { @MainActor in
                ControlServer.shared.receive(connection, buffer: Data())
            }
        }
        listener.stateUpdateHandler = { state in
            Task { @MainActor in
                ControlServer.shared.listenerChanged(state, listener: listener, port: candidate, remaining: remaining)
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    private func listenerChanged(_ state: NWListener.State, listener: NWListener, port: UInt16, remaining: Int) {
        switch state {
        case .ready:
            starting = false
            writeEndpoint(port: port)
        case .failed:
            listener.cancel()
            if self.listener === listener { self.listener = nil }
            attempt(remaining: remaining - 1)
        default:
            break
        }
    }

    private func writeEndpoint(port: UInt16) {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kterm", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let url = dir.appendingPathComponent("endpoint.json")
            let body: [String: Any] = ["port": Int(port), "token": token]
            let data = try JSONSerialization.data(withJSONObject: body)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("kterm: failed to write control endpoint: \(error)")
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            Task { @MainActor in
                var next = buffer
                if let data { next.append(data) }
                if next.count > 300_000 {
                    self.finish(connection, status: 413, json: Self.encode(["error": "payload too large"]))
                    return
                }
                switch HTTPRequest.parse(next) {
                case .needMore:
                    if error != nil || isComplete {
                        connection.cancel()
                    } else {
                        self.receive(connection, buffer: next)
                    }
                case .tooLarge:
                    self.finish(connection, status: 413, json: Self.encode(["error": "payload too large"]))
                case .bad:
                    self.finish(connection, status: 400, json: Self.encode(["error": "bad request"]))
                case .ready(let request):
                    let response = self.route(method: request.method, path: request.path,
                                              headers: request.headers, body: request.body)
                    self.finish(connection, status: response.status, json: response.json)
                }
            }
        }
    }

    private func finish(_ connection: NWConnection, status: Int, json: Data) {
        let reason = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        default: "Error"
        }
        var packet = Data("HTTP/1.1 \(status) \(reason)\r\n".utf8)
        packet.append(Data("Content-Type: application/json\r\n".utf8))
        packet.append(Data("Content-Length: \(json.count)\r\n".utf8))
        packet.append(Data("Connection: close\r\n\r\n".utf8))
        packet.append(json)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    /// Parsed far enough to answer, or still waiting on the body.
    private enum HTTPRequest {
        case needMore
        case bad
        case tooLarge
        case ready(Request)

        static func parse(_ data: Data) -> HTTPRequest {
            guard let marker = data.range(of: Data("\r\n\r\n".utf8)) else { return .needMore }
            let head = data[..<marker.lowerBound]
            let rest = data[marker.upperBound...]
            guard let text = String(data: head, encoding: .utf8) else { return .bad }
            let lines = text.components(separatedBy: "\r\n")
            let parts = lines.first?.split(separator: " ", maxSplits: 2) ?? []
            guard parts.count >= 2 else { return .bad }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            if length > 256 * 1024 { return .tooLarge }
            if rest.count < length { return .needMore }
            let body = Data(rest.prefix(length))
            let path = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
            return .ready(Request(method: String(parts[0]), path: path, headers: headers, body: body))
        }
    }

    private func route(method: String, path: String, headers: [String: String], body: Data) -> (status: Int, json: Data) {
        guard headers["authorization"] == "Bearer \(token)" else {
            return (401, Self.encode(["error": "unauthorized"]))
        }
        let pieces = path.split(separator: "/").map(String.init)
        if method == "GET", pieces == ["tabs"] {
            let panes = AppModel.listPanes().map {
                PaneBody(id: $0.id.uuidString, title: $0.title, pwd: $0.pwd, agent: $0.agent,
                         focused: $0.focused, group: $0.group, tab: $0.tab, pane: $0.pane)
            }
            return (200, Self.encode(panes))
        }
        if method == "POST", pieces == ["tabs"] {
            return createTab(body)
        }
        if pieces.count == 3, pieces[0] == "tabs", let id = UUID(uuidString: pieces[1]) {
            switch (method, pieces[2]) {
            case ("POST", "focus"):
                let before = AppModel.listPanes().contains { $0.id == id }
                guard before else { return (404, Self.encode(["error": "no such tab"])) }
                AppModel.focusTerminalAnyWindow(withID: id)
                return (200, Self.encode(["ok": true]))
            case ("POST", "send"):
                return send(id: id, body: body)
            case ("GET", "read"):
                guard let text = AppModel.read(id: id) else {
                    return (404, Self.encode(["error": "no such tab"]))
                }
                return (200, Self.encode(ReadBody(text: text)))
            default:
                break
            }
        }
        return (404, Self.encode(["error": "not found"]))
    }

    private func createTab(_ body: Data) -> (status: Int, json: Data) {
        guard let request = try? JSONDecoder().decode(NewTabBody.self, from: body) else {
            return (400, Self.encode(["error": "expected {agent, cwd?, prompt?}"]))
        }
        if let prompt = request.prompt, prompt.utf8.count > 64 * 1024 {
            return (400, Self.encode(["error": "prompt too large"]))
        }
        if let cwd = request.cwd {
            var isDir = ObjCBool(false)
            guard cwd.hasPrefix("/"),
                  FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir),
                  isDir.boolValue
            else { return (400, Self.encode(["error": "cwd is not a directory"])) }
        }
        guard let model = AppModel.front() else {
            return (400, Self.encode(["error": "no kterm window"]))
        }
        let id: UUID?
        if request.agent == "shell" {
            id = model.newCommandTab(command: nil, agent: nil, title: nil,
                                     cwd: request.cwd, prompt: request.prompt)
        } else if let agent = KtermAgent(rawValue: request.agent) {
            id = model.newAgentTab(agent, cwd: request.cwd, prompt: request.prompt)
        } else {
            return (400, Self.encode(["error": "unknown agent"]))
        }
        guard let id else { return (400, Self.encode(["error": "could not open tab"])) }
        NSApp.activate(ignoringOtherApps: true)
        model.window?.makeKeyAndOrderFront(nil)
        return (200, Self.encode(["id": id.uuidString]))
    }

    private func send(id: UUID, body: Data) -> (status: Int, json: Data) {
        guard let request = try? JSONDecoder().decode(SendBody.self, from: body) else {
            return (400, Self.encode(["error": "expected {text, enter?}"]))
        }
        if request.text.utf8.count > 256 * 1024 {
            return (413, Self.encode(["error": "payload too large"]))
        }
        guard AppModel.listPanes().contains(where: { $0.id == id }) else {
            return (404, Self.encode(["error": "no such tab"]))
        }
        guard AppModel.send(to: id, text: request.text, enter: request.enter ?? false) else {
            return (400, Self.encode(["error": "empty send"]))
        }
        return (200, Self.encode(["ok": true]))
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}

private struct PaneBody: Encodable {
    var id: String
    var title: String
    var pwd: String
    var agent: String?
    var focused: Bool
    var group: Int
    var tab: Int
    var pane: Int
}

private struct NewTabBody: Decodable {
    var agent: String
    var cwd: String?
    var prompt: String?
}

private struct SendBody: Decodable {
    var text: String
    var enter: Bool?
}

private struct ReadBody: Encodable {
    var text: String
}
