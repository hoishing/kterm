import AppKit
import Foundation
import Network
import Security

/// Loopback HTTP API for `ktermctl` (`Resources/bin/ktermctl`). Binds 127.0.0.1 and requires the
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
                    self.route(request) { status, json in
                        self.finish(connection, status: status, json: json)
                    }
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
        case 408: "Request Timeout"
        case 413: "Payload Too Large"
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
        var query: [String: String]
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
            let target = String(parts[1]).split(separator: "?", maxSplits: 1).map(String.init)
            var query: [String: String] = [:]
            if target.count == 2 {
                for pair in target[1].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    guard let key = kv.first?.removingPercentEncoding else { continue }
                    query[key] = kv.count == 2 ? (kv[1].removingPercentEncoding ?? kv[1]) : ""
                }
            }
            return .ready(Request(method: String(parts[0]), path: target.first ?? "/",
                                  query: query, headers: headers, body: body))
        }
    }

    private typealias Reply = (_ status: Int, _ json: Data) -> Void

    private func route(_ request: Request, reply: @escaping Reply) {
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return reply(401, Self.encode(["error": "unauthorized"]))
        }
        let pieces = request.path.split(separator: "/").map(String.init)
        if request.method == "GET", pieces == ["tabs"] {
            let panes = AppModel.listPanes().map {
                PaneBody(id: $0.id.uuidString, title: $0.title, pwd: $0.pwd, agent: $0.agent,
                         exited: $0.exited, focused: $0.focused,
                         group: $0.group, tab: $0.tab, pane: $0.pane)
            }
            return reply(200, Self.encode(panes))
        }
        if request.method == "POST", pieces == ["tabs"] {
            let response = createTab(request.body)
            return reply(response.status, response.json)
        }
        guard pieces.count == 3, pieces[0] == "tabs", let id = UUID(uuidString: pieces[1]) else {
            return reply(404, Self.encode(["error": "not found"]))
        }
        guard AppModel.locatePane(id) != nil else {
            return reply(404, Self.encode(["error": "no such tab"]))
        }
        switch (request.method, pieces[2]) {
        case ("POST", "focus"):
            AppModel.focusTerminalAnyWindow(withID: id)
            reply(200, Self.encode(["ok": true]))
        case ("POST", "close"):
            AppModel.closePane(id: id)
            reply(200, Self.encode(["ok": true]))
        case ("POST", "send"):
            let response = send(id: id, body: request.body)
            reply(response.status, response.json)
        case ("GET", "read"):
            let lines = request.query["lines"].flatMap { Int($0) }
            let text = AppModel.read(id: id, lines: lines) ?? ""
            reply(200, Self.encode(ReadBody(text: text)))
        case ("GET", "wait"):
            wait(id: id, query: request.query, reply: reply)
        default:
            reply(404, Self.encode(["error": "not found"]))
        }
    }

    private func createTab(_ body: Data) -> (status: Int, json: Data) {
        guard let request = try? JSONDecoder().decode(NewTabBody.self, from: body) else {
            return (400, Self.encode(["error": "expected {agent, cwd?, prompt?, from?, background?}"]))
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
        let agent: KtermAgent?
        if request.agent == "shell" {
            agent = nil
        } else if let known = KtermAgent(rawValue: request.agent) {
            agent = known
        } else {
            return (400, Self.encode(["error": "unknown agent"]))
        }
        // `from` is the caller's `KTERM_TAB_ID`: open next to it, in its
        // window. A stale id falls back to the front window.
        let caller = request.from.flatMap(UUID.init(uuidString:)).flatMap(AppModel.locatePane)
        guard let model = caller?.model ?? AppModel.front() else {
            return (400, Self.encode(["error": "no kterm window"]))
        }
        let background = request.background ?? false
        guard let id = model.spawnTab(agent: agent, cwd: request.cwd, prompt: request.prompt,
                                      after: caller, background: background)
        else { return (400, Self.encode(["error": "could not open tab"])) }
        if !background {
            NSApp.activate(ignoringOtherApps: true)
            model.window?.makeKeyAndOrderFront(nil)
        }
        return (200, Self.encode(["id": id.uuidString]))
    }

    private func send(id: UUID, body: Data) -> (status: Int, json: Data) {
        guard let request = try? JSONDecoder().decode(SendBody.self, from: body) else {
            return (400, Self.encode(["error": "expected {text, enter?}"]))
        }
        if request.text.utf8.count > 256 * 1024 {
            return (413, Self.encode(["error": "payload too large"]))
        }
        guard AppModel.send(to: id, text: request.text, enter: request.enter ?? false) else {
            return (400, Self.encode(["error": "empty send"]))
        }
        return (200, Self.encode(["ok": true]))
    }

    /// Long-poll until the pane settles. `for=exit` waits for its process to
    /// exit (or the pane to close). `for=idle` (default) waits until the
    /// visible screen has not changed for `quiet_ms` — agent TUIs animate a
    /// spinner or timer while working, so a still screen means done or
    /// waiting for input. Answers 408 `{"state":"timeout"}` after `timeout_ms`.
    private func wait(id: UUID, query: [String: String], reply: @escaping Reply) {
        let forExit = query["for"] == "exit"
        let quiet = Double(query["quiet_ms"].flatMap { Int($0) } ?? 3000) / 1000
        let timeout = Double(min(query["timeout_ms"].flatMap { Int($0) } ?? 300_000, 3_600_000)) / 1000
        let started = Date()
        var lastScreen: String?
        var lastChange = Date()
        let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
            MainActor.assumeIsolated {
                func done(_ status: Int, _ state: String) {
                    timer.invalidate()
                    reply(status, Self.encode(["state": state]))
                }
                guard let view = AppModel.locatePane(id)?.term.surfaceView else {
                    return done(200, "closed")
                }
                if view.processExited { return done(200, "exited") }
                let now = Date()
                if !forExit {
                    let screen = view.readText(viewport: true)
                    if screen != lastScreen {
                        lastScreen = screen
                        lastChange = now
                    } else if now.timeIntervalSince(lastChange) >= quiet {
                        return done(200, "idle")
                    }
                }
                if now.timeIntervalSince(started) >= timeout { done(408, "timeout") }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    nonisolated private static func encode<T: Encodable>(_ value: T) -> Data {
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
    var exited: Bool
    var focused: Bool
    var group: Int
    var tab: Int
    var pane: Int
}

private struct NewTabBody: Decodable {
    var agent: String
    var cwd: String?
    var prompt: String?
    /// Caller's `KTERM_TAB_ID`.
    var from: String?
    /// Do not select, focus, or raise the new tab.
    var background: Bool?
}

private struct SendBody: Decodable {
    var text: String
    var enter: Bool?
}

private struct ReadBody: Encodable {
    var text: String
}
