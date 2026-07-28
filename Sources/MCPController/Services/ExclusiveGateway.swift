import Foundation
import Network

struct GatewayLeaseSnapshot: Identifiable, Equatable, Sendable {
    var id: String { clientID }
    let clientID: String
    let clientName: String
    let acquiredAt: Date
    let lastSeenAt: Date
}

struct GatewayPendingSnapshot: Identifiable, Equatable, Sendable {
    var id: String { clientID }
    let clientID: String
    let clientName: String
    let requestedAt: Date
}

enum LeaseDecision: Equatable {
    case allowed
    case waiting
}

struct ExclusiveLeaseArbiter: Sendable {
    private(set) var active: GatewayLeaseSnapshot?
    private(set) var pending: [GatewayPendingSnapshot] = []
    var timeout: TimeInterval

    mutating func authorize(clientID: String, clientName: String, now: Date = Date()) -> LeaseDecision {
        if let lease = active, now.timeIntervalSince(lease.lastSeenAt) >= timeout {
            active = nil
        }
        if let lease = active {
            if lease.clientID == clientID {
                active = GatewayLeaseSnapshot(
                    clientID: clientID,
                    clientName: clientName,
                    acquiredAt: lease.acquiredAt,
                    lastSeenAt: now
                )
                pending.removeAll { $0.clientID == clientID }
                return .allowed
            }
            if !pending.contains(where: { $0.clientID == clientID }) {
                pending.append(GatewayPendingSnapshot(clientID: clientID, clientName: clientName, requestedAt: now))
            }
            return .waiting
        }
        active = GatewayLeaseSnapshot(clientID: clientID, clientName: clientName, acquiredAt: now, lastSeenAt: now)
        pending.removeAll { $0.clientID == clientID }
        return .allowed
    }

    mutating func approve(clientID: String, now: Date = Date()) {
        guard let request = pending.first(where: { $0.clientID == clientID }) else { return }
        active = GatewayLeaseSnapshot(clientID: request.clientID, clientName: request.clientName, acquiredAt: now, lastSeenAt: now)
        pending.removeAll { $0.clientID == clientID }
    }

    mutating func deny(clientID: String) {
        pending.removeAll { $0.clientID == clientID }
    }

    mutating func release() {
        active = nil
    }
}

final class ExclusiveGatewayManager: @unchecked Sendable {
    typealias StateHandler = @Sendable (UUID, GatewayLeaseSnapshot?, [GatewayPendingSnapshot]) -> Void
    typealias LogHandler = @Sendable (UUID, String) -> Void

    var onStateChange: StateHandler?
    var onLog: LogHandler?

    private let lock = NSLock()
    private var gateways: [UUID: ExclusiveGateway] = [:]

    func start(profile: ServerProfile) throws {
        guard profile.exclusiveGatewayEnabled else { return }
        stop(profileID: profile.id)
        let gateway = try ExclusiveGateway(
            profile: profile,
            stateHandler: { [weak self] active, pending in
                self?.onStateChange?(profile.id, active, pending)
            },
            logHandler: { [weak self] message in
                self?.onLog?(profile.id, message)
            }
        )
        lock.lock()
        gateways[profile.id] = gateway
        lock.unlock()
        gateway.start()
    }

    func stop(profileID: UUID) {
        lock.lock()
        let gateway = gateways.removeValue(forKey: profileID)
        lock.unlock()
        gateway?.stop()
        onStateChange?(profileID, nil, [])
    }

    func approve(profileID: UUID, clientID: String) {
        withGateway(profileID) { $0.approve(clientID: clientID) }
    }

    func deny(profileID: UUID, clientID: String) {
        withGateway(profileID) { $0.deny(clientID: clientID) }
    }

    func release(profileID: UUID) {
        withGateway(profileID) { $0.release() }
    }

    private func withGateway(_ profileID: UUID, action: (ExclusiveGateway) -> Void) {
        lock.lock()
        let gateway = gateways[profileID]
        lock.unlock()
        if let gateway { action(gateway) }
    }
}

private final class ExclusiveGateway: @unchecked Sendable {
    private let profile: ServerProfile
    private let queue: DispatchQueue
    private let listener: NWListener
    private let stateHandler: @Sendable (GatewayLeaseSnapshot?, [GatewayPendingSnapshot]) -> Void
    private let logHandler: @Sendable (String) -> Void
    private var arbiter: ExclusiveLeaseArbiter

    init(
        profile: ServerProfile,
        stateHandler: @escaping @Sendable (GatewayLeaseSnapshot?, [GatewayPendingSnapshot]) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) throws {
        self.profile = profile
        self.stateHandler = stateHandler
        self.logHandler = logHandler
        self.arbiter = ExclusiveLeaseArbiter(timeout: TimeInterval(profile.leaseTimeoutSeconds))
        self.queue = DispatchQueue(label: "com.versyi.mcp-controller.gateway.\(profile.id.uuidString)")
        guard let port = NWEndpoint.Port(rawValue: UInt16(profile.gatewayPort)) else {
            throw GatewayError.invalidPort
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        self.listener = try NWListener(using: parameters)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logHandler("Exclusive gateway listening on 127.0.0.1:\(self.profile.gatewayPort).\n")
            case .failed(let error):
                self.logHandler("Exclusive gateway failed: \(error.localizedDescription)\n")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            self?.listener.cancel()
            self?.arbiter.release()
            self?.publishState()
        }
    }

    func approve(clientID: String) {
        queue.async { [weak self] in
            self?.arbiter.approve(clientID: clientID)
            self?.publishState()
            self?.logHandler("Exclusive access approved for a waiting AI. It may retry now.\n")
        }
    }

    func deny(clientID: String) {
        queue.async { [weak self] in
            self?.arbiter.deny(clientID: clientID)
            self?.publishState()
        }
    }

    func release() {
        queue.async { [weak self] in
            self?.arbiter.release()
            self?.publishState()
            self?.logHandler("Exclusive AI lease released by the user.\n")
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var next = buffer
            if let data { next.append(data) }
            if next.count > 2_097_152 {
                self.sendError(connection, status: 413, message: "MCP request is too large.", requestID: NSNull())
                return
            }
            if let request = HTTPRequest.parse(next) {
                self.handle(request, connection: connection)
                return
            }
            if isComplete || error != nil {
                self.sendError(connection, status: 400, message: "Malformed HTTP request.", requestID: NSNull())
                return
            }
            self.receive(connection, buffer: next)
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        guard request.method == "POST" || request.method == "DELETE" else {
            sendError(connection, status: 405, message: "This gateway accepts MCP POST and DELETE requests. SSE GET is not enabled.", requestID: request.jsonRPCID)
            return
        }
        if let origin = request.headers["origin"], !profile.allowedOrigins.contains(origin) {
            sendError(connection, status: 403, message: "Origin is not allowed by this MCP gateway.", requestID: request.jsonRPCID)
            return
        }
        guard let authorization = request.headers["authorization"], authorization.lowercased().hasPrefix("bearer ") else {
            sendError(connection, status: 401, message: "A per-AI Bearer access key is required.", requestID: request.jsonRPCID)
            return
        }
        let token = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        guard let credential = profile.clientCredentials.first(where: { $0.token == token }) else {
            sendError(connection, status: 401, message: "The MCP Controller access key is invalid.", requestID: request.jsonRPCID)
            return
        }

        switch arbiter.authorize(clientID: credential.id.uuidString, clientName: credential.name) {
        case .allowed:
            publishState()
            proxy(request, credential: credential, connection: connection)
        case .waiting:
            publishState()
            logHandler("\(credential.name) requested access while another AI holds the lease.\n")
            sendError(
                connection,
                status: 409,
                message: "Connection in use. Please wait for user confirmation, then retry.",
                requestID: request.jsonRPCID,
                data: ["retryable": true, "state": "waiting_for_user_confirmation"]
            )
        }
    }

    private func proxy(_ request: HTTPRequest, credential: GatewayClientCredential, connection: NWConnection) {
        let target = upstreamTarget(for: request.target)
        guard let url = URL(string: "http://127.0.0.1:\(profile.localPort)\(target)") else {
            sendError(connection, status: 502, message: "The upstream MCP URL is invalid.", requestID: request.jsonRPCID)
            return
        }
        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method
        upstream.httpBody = request.body
        upstream.timeoutInterval = 60
        for (name, value) in request.headers {
            guard !["authorization", "host", "connection", "content-length", "transfer-encoding", "origin"].contains(name) else { continue }
            upstream.setValue(value, forHTTPHeaderField: name)
        }
        upstream.setValue("MCP Controller", forHTTPHeaderField: "User-Agent")

        Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: upstream)
                guard let http = response as? HTTPURLResponse else {
                    self.sendError(connection, status: 502, message: "Upstream MCP returned an invalid response.", requestID: request.jsonRPCID)
                    return
                }
                try await self.sendChunkedProxyResponse(connection, response: http, bytes: bytes)
                if request.method == "DELETE", (200..<300).contains(http.statusCode) {
                    self.queue.async {
                        self.arbiter.release()
                        self.publishState()
                    }
                }
            } catch {
                self.sendError(connection, status: 502, message: "Upstream MCP is unavailable: \(error.localizedDescription)", requestID: request.jsonRPCID)
            }
        }
    }

    private func upstreamTarget(for requestTarget: String) -> String {
        let mount = profile.normalizedMountPath
        guard mount != "/" else { return requestTarget }
        if requestTarget == mount { return "/" }
        let prefix = mount + "/"
        if requestTarget.hasPrefix(prefix) {
            let stripped = String(requestTarget.dropFirst(mount.count))
            return stripped.isEmpty ? "/" : stripped
        }
        return requestTarget
    }

    private func sendChunkedProxyResponse(
        _ connection: NWConnection,
        response: HTTPURLResponse,
        bytes: URLSession.AsyncBytes
    ) async throws {
        var headers = "HTTP/1.1 \(response.statusCode) \(HTTPStatus.reason(response.statusCode))\r\n"
        for (key, value) in response.allHeaderFields {
            let name = String(describing: key)
            guard !["content-length", "transfer-encoding", "connection"].contains(name.lowercased()) else { continue }
            headers += "\(name): \(value)\r\n"
        }
        headers += "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        try await sendAsync(connection, data: Data(headers.utf8))

        var buffer = Data()
        var iterator = bytes.makeAsyncIterator()
        while let byte = try await iterator.next() {
            buffer.append(byte)
            if buffer.count >= 1024 {
                try await sendChunk(connection, body: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try await sendChunk(connection, body: buffer)
        }
        try await sendAsync(connection, data: Data("0\r\n\r\n".utf8))
        connection.cancel()
    }

    private func sendChunk(_ connection: NWConnection, body: Data) async throws {
        var chunk = Data(String(body.count, radix: 16).utf8)
        chunk.append(Data("\r\n".utf8))
        chunk.append(body)
        chunk.append(Data("\r\n".utf8))
        try await sendAsync(connection, data: chunk)
    }

    private func sendAsync(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            })
        }
    }

    private func sendError(
        _ connection: NWConnection,
        status: Int,
        message: String,
        requestID: Any,
        data: [String: Any]? = nil
    ) {
        var errorObject: [String: Any] = ["code": -32001, "message": message]
        if let data { errorObject["data"] = data }
        let object: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "error": errorObject]
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        let headers = "HTTP/1.1 \(status) \(HTTPStatus.reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        send(connection, data: response)
    }

    private func send(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func publishState() {
        stateHandler(arbiter.active, arbiter.pending.sorted { $0.requestedAt < $1.requestedAt })
    }
}

private struct HTTPRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let body: Data

    var jsonRPCID: Any {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return NSNull() }
        return object["id"] ?? NSNull()
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator), let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestParts = first.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let split = line.firstIndex(of: ":") else { continue }
            let name = line[..<split].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { return nil }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return HTTPRequest(method: String(requestParts[0]).uppercased(), target: String(requestParts[1]), headers: headers, body: body)
    }
}

private enum HTTPStatus {
    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Content Too Large"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        default: "Response"
        }
    }
}

enum GatewayError: LocalizedError {
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidPort: "The exclusive gateway port is invalid."
        }
    }
}
