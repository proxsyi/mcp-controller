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
        for _ in 0..<20 where PortInspector.listener(on: profile.gatewayPort) != nil {
            Thread.sleep(forTimeInterval: 0.05)
        }
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

private final class GatewayRequestDeadline: @unchecked Sendable {
    private(set) var finished = false
    private(set) var responseStarted = false

    func markResponseStarted() {
        responseStarted = true
    }

    func claim() -> Bool {
        guard !finished else { return false }
        finished = true
        return true
    }
}

private final class ExclusiveGateway: @unchecked Sendable {
    private let profile: ServerProfile
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let listener: NWListener
    private let stateHandler: @Sendable (GatewayLeaseSnapshot?, [GatewayPendingSnapshot]) -> Void
    private let logHandler: @Sendable (String) -> Void
    private var arbiter: ExclusiveLeaseArbiter
    private var bridgedProtocolVersions: [String: String] = [:]
    private var upstreamCapabilities: [String: Set<String>] = [:]

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
        self.queue.setSpecific(key: queueKey, value: ())
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
        let shutdown = { [self] in
            listener.cancel()
            arbiter.release()
            publishState()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            shutdown()
        } else {
            queue.sync(execute: shutdown)
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
            self.processIncomingData(connection, buffer: next, isComplete: isComplete, didError: error != nil)
        }
    }

    private func processIncomingData(_ connection: NWConnection, buffer: Data, isComplete: Bool = false, didError: Bool = false) {
        if buffer.count > 2_097_152 {
            sendError(connection, status: 413, message: "MCP request is too large.", requestID: NSNull())
            return
        }
        if let parsed = HTTPRequest.parse(buffer) {
            let remainder = buffer.count > parsed.bytesConsumed ? Data(buffer[parsed.bytesConsumed..<buffer.count]) : Data()
            handle(parsed.request, connection: connection, bufferedData: remainder)
            return
        }
        if isComplete || didError {
            sendError(connection, status: 400, message: "Malformed HTTP request.", requestID: NSNull())
            return
        }
        receive(connection, buffer: buffer)
    }

    private func continueReceiving(on connection: NWConnection, bufferedData: Data = Data()) {
        if bufferedData.isEmpty {
            receive(connection, buffer: Data())
        } else {
            processIncomingData(connection, buffer: bufferedData)
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection, bufferedData: Data = Data()) {
        let session = request.headers["mcp-session-id"].map { "present (\($0.prefix(8))…)" } ?? "none"
        let accept = request.headers["accept"] ?? "none"
        let protocolVersion = request.headers["mcp-protocol-version"] ?? request.requestedProtocolVersion ?? "none"
        let rpcMethod = request.jsonRPCMethod ?? "none"
        let cancelTarget = request.cancellationTargetDescription ?? "none"
        let requestIDDescription = request.requestIDDescription
        logHandler("Gateway request: \(request.method) \(request.target); id=\(requestIDDescription); rpc=\(rpcMethod); cancel=\(cancelTarget); session=\(session); accept=\(accept); protocol=\(protocolVersion); compatibility=\(profile.remoteClientCompatibilityEnabled).\n")
        guard GatewayRequestMethodPolicy.accepts(
            request.method,
            remoteClientCompatibilityEnabled: profile.remoteClientCompatibilityEnabled
        ) else {
            sendError(connection, status: 405, message: "This gateway accepts MCP POST, GET, DELETE, and OPTIONS requests. Remote compatibility also accepts HEAD probes.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
            return
        }
        if let origin = request.headers["origin"], !isAllowedOrigin(origin) {
            sendError(connection, status: 403, message: "Origin is not allowed by this MCP gateway.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
            return
        }
        if request.method == "OPTIONS" {
            sendPreflightOK(
                connection,
                origin: request.headers["origin"],
                requestedHeaders: request.headers["access-control-request-headers"],
                bufferedData: bufferedData
            )
            return
        }
        if request.method == "HEAD" {
            logHandler("Compatibility probe accepted with HTTP 200.\n")
            sendHeadOK(connection, bufferedData: bufferedData)
            return
        }
        if profile.remoteClientCompatibilityEnabled,
           let sessionID = request.headers["mcp-session-id"],
           let method = request.jsonRPCMethod {
            let compatibilityResult: [String: Any]?
            switch method {
            case "resources/templates/list":
                compatibilityResult = ["resourceTemplates": []]
            case "resources/list":
                compatibilityResult = ["resources": []]
            case "prompts/list":
                compatibilityResult = ["prompts": []]
            default:
                compatibilityResult = nil
            }
            if let result = compatibilityResult {
                logHandler("Compatibility fallback: returned an empty \(method) result for Notion compatibility.\n")
                logHandler("Compatibility fallback response: method=\(method), contentType=text/event-stream, session=\(sessionID.prefix(8))….\n")
                sendCompatibilityResult(
                    connection,
                    requestID: request.jsonRPCID,
                    sessionID: sessionID,
                    protocolVersion: bridgedProtocolVersions[sessionID] ?? request.headers["mcp-protocol-version"],
                    result: result
                )
                return
            }
        }
        if request.method == "GET" {
            if let _ = request.headers["mcp-session-id"] {
                guard let credential = authorizedCredential(for: request) else {
                    sendError(connection, status: 401, message: "A per-AI Bearer access key is required.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
                    return
                }
                guard let activeLease = arbiter.active else {
                    sendError(connection, status: 404, message: "The MCP session is no longer active. Initialize again and retry.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
                    return
                }
                guard activeLease.clientID == credential.id.uuidString else {
                    sendError(connection, status: 403, message: "This session belongs to a different authorized AI client.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
                    return
                }
                _ = arbiter.authorize(clientID: credential.id.uuidString, clientName: credential.name)
                publishState()
                if profile.remoteClientCompatibilityEnabled {
                    logHandler("Compatibility session stream attached locally.\n")
                    sendCompatibilitySessionStream(connection)
                } else {
                    proxy(request, connection: connection, bufferedDataAfterResponse: bufferedData)
                }
                return
            }

            guard profile.remoteClientCompatibilityEnabled else {
                sendError(connection, status: 405, message: "This MCP endpoint does not offer a pre-session SSE stream. Initialize with POST first, then retry GET with Mcp-Session-Id.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
                return
            }

            guard let credential = authorizedCredential(for: request) else {
                sendError(connection, status: 401, message: "A per-AI Bearer access key is required.", requestID: request.jsonRPCID, keepConnectionOpen: true, bufferedData: bufferedData)
                return
            }

            switch arbiter.authorize(clientID: credential.id.uuidString, clientName: credential.name) {
            case .allowed:
                publishState()
                sendCompatibilityHandshake(request, connection: connection)
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
            return
        }

        guard let credential = authorizedCredential(for: request) else {
            sendError(connection, status: 401, message: "A per-AI Bearer access key is required.", requestID: request.jsonRPCID)
            return
        }

        switch arbiter.authorize(clientID: credential.id.uuidString, clientName: credential.name) {
        case .allowed:
            publishState()
            proxy(request, connection: connection, bufferedDataAfterResponse: bufferedData)
        case .waiting:
            publishState()
            logHandler("\(credential.name) requested access while another AI holds the lease.\n")
            sendError(
                connection,
                status: 409,
                message: "Connection in use. Please wait for user confirmation, then retry.",
                requestID: request.jsonRPCID,
                data: ["retryable": true, "state": "waiting_for_user_confirmation"],
                keepConnectionOpen: true,
                bufferedData: bufferedData
            )
        }
    }

    private func isAllowedOrigin(_ origin: String) -> Bool {
        let configured = profile.allowedOrigins.map(Self.normalizedOrigin)
        guard !configured.isEmpty else { return false }
        let normalized = Self.normalizedOrigin(origin)
        return configured.contains(normalized)
    }

    private static func normalizedOrigin(_ origin: String) -> String {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return trimmed.lowercased()
        }
        let effectivePort = components.port ?? defaultPort(for: scheme)
        return "\(scheme)://\(host):\(effectivePort)"
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme {
        case "http": 80
        case "https": 443
        default: 0
        }
    }

    private func authorizedCredential(for request: HTTPRequest) -> GatewayClientCredential? {
        guard let authorization = request.headers["authorization"], authorization.lowercased().hasPrefix("bearer ") else {
            return nil
        }
        let token = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        return profile.clientCredentials.first(where: { $0.token == token })
    }

    private func sendCompatibilitySessionStream(_ connection: NWConnection) {
        let eventID = "\(UUID().uuidString)_\(Int(Date().timeIntervalSince1970 * 1000))_0000_gek"
        let body = Data(("id: \(eventID)\ndata: \n\n").utf8)
        let headers = "HTTP/1.1 200 OK\r\nCache-Control: no-cache\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n"
        var payload = Data(headers.utf8)
        payload.append(HTTPChunkedBodyEncoder.encode(body))
        connection.send(content: payload, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            if let error {
                self.logHandler("Compatibility session stream failed: \(error.localizedDescription)\n")
                connection.cancel()
            } else {
                self.scheduleCompatibilitySessionKeepalive(connection)
            }
        })
    }

    private func scheduleCompatibilitySessionKeepalive(_ connection: NWConnection) {
        queue.asyncAfter(deadline: .now() + 15) { [weak self, weak connection] in
            guard let self, let connection else { return }
            let keepalive = HTTPChunkedBodyEncoder.encode(Data(": keepalive\n\n".utf8))
            connection.send(content: keepalive, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection else { return }
                if let error {
                    self.logHandler("Compatibility session keepalive ended: \(error.localizedDescription)\n")
                    connection.cancel()
                } else {
                    self.scheduleCompatibilitySessionKeepalive(connection)
                }
            })
        }
    }

    private func sendCompatibilityHandshake(_ request: HTTPRequest, connection: NWConnection) {
        let forwardedProto = request.headers["x-forwarded-proto"]
        let host = request.headers["x-forwarded-host"] ?? request.headers["host"] ?? "127.0.0.1:\(profile.gatewayPort)"
        let scheme: String
        if let forwardedProto, !forwardedProto.isEmpty {
            scheme = forwardedProto
        } else if host.contains("127.0.0.1") || host.contains("localhost") {
            scheme = "http"
        } else {
            scheme = "https"
        }
        let publicTarget = GatewayRouteMapper.publicTarget(
            for: request.target,
            forwardedPrefix: request.headers["x-forwarded-prefix"],
            profile: profile
        )
        let endpoint = "\(scheme)://\(host)\(publicTarget)"
        let body = Data(("event: endpoint\r\ndata: \(endpoint)\r\n\r\n" + ": connected\r\n\r\n").utf8)
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache, no-transform\r\nX-Accel-Buffering: no\r\nTransfer-Encoding: chunked\r\nConnection: keep-alive\r\n\r\n"
        var payload = Data(headers.utf8)
        payload.append(HTTPChunkedBodyEncoder.encode(body))
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                self.logHandler("Compatibility handshake failed: \(error.localizedDescription)\n")
                connection.cancel()
            }
        })
    }

    private func proxy(_ request: HTTPRequest, connection: NWConnection, bufferedDataAfterResponse: Data = Data()) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(profile.localPort)) else {
            sendError(connection, status: 502, message: "The upstream MCP port is invalid.", requestID: request.jsonRPCID)
            return
        }

        let target = GatewayRouteMapper.upstreamTarget(for: request.target, profile: profile)
        let responseBridge: GatewayInitializeResponseBridge?
        if profile.remoteClientCompatibilityEnabled, let requestedVersion = request.requestedProtocolVersion {
            responseBridge = GatewayInitializeResponseBridge(requestedVersion: requestedVersion)
        } else {
            responseBridge = nil
        }
        let upstream = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let deadline = GatewayRequestDeadline()
        if GatewayRequestDeadlinePolicy.applies(to: request.method) {
            queue.asyncAfter(deadline: .now() + TimeInterval(profile.publicRequestTimeoutSeconds)) { [weak self, weak upstream, weak connection] in
                guard let self, let upstream, let connection, deadline.claim() else { return }
                self.logHandler("Public MCP request timed out after \(self.profile.publicRequestTimeoutSeconds) seconds.\n")
                upstream.cancel()
                if deadline.responseStarted {
                    connection.cancel()
                } else {
                    self.sendError(connection, status: 504, message: "The MCP request exceeded this route’s \(self.profile.publicRequestTimeoutSeconds)-second timeout.", requestID: request.jsonRPCID)
                }
            }
        }
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                upstream.stateUpdateHandler = nil
                let payload = self.upstreamRequestData(request, target: target)
                upstream.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        guard deadline.claim() else { return }
                        self.sendError(connection, status: 502, message: "Upstream MCP request failed: \(error.localizedDescription)", requestID: request.jsonRPCID)
                        upstream.cancel()
                    } else if self.profile.remoteClientCompatibilityEnabled && request.isJSONRPCNotification {
                        _ = deadline.claim()
                        self.logHandler("Compatibility acknowledgement: accepted JSON-RPC notification \(request.jsonRPCMethod ?? "unknown") for upstream delivery.\n")
                        self.sendAccepted(connection)
                        self.drainUpstreamResponse(upstream)
                    } else {
                        self.pipeUpstreamResponse(upstream, to: connection, initializeBridge: responseBridge, bufferedDataAfterResponse: bufferedDataAfterResponse, deadline: deadline)
                    }
                })
            case .failed(let error):
                guard deadline.claim() else { return }
                self.sendError(connection, status: 502, message: "Upstream MCP is unavailable: \(error.localizedDescription)", requestID: request.jsonRPCID)
                upstream.cancel()
            case .cancelled:
                break
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func upstreamRequestData(_ request: HTTPRequest, target: String) -> Data {
        let excludedHeaders = upstreamExcludedHeaders(for: request)
        var headers = "\(request.method) \(target) HTTP/1.1\r\n"
        headers += "Host: 127.0.0.1:\(profile.localPort)\r\n"
        for (name, value) in request.headers.sorted(by: { $0.key < $1.key }) {
            guard !excludedHeaders.contains(name) else { continue }
            headers += "\(name): \(value)\r\n"
        }
        var protocolVersion = request.headers["mcp-protocol-version"]
        if profile.remoteClientCompatibilityEnabled,
           let sessionID = request.headers["mcp-session-id"],
           let bridgedVersion = bridgedProtocolVersions[sessionID] {
            protocolVersion = bridgedVersion
        }
        if let protocolVersion {
            headers += "MCP-Protocol-Version: \(protocolVersion)\r\n"
        }
        if let accept = GatewayRequestHeaderAdapter.acceptValue(
            original: request.headers["accept"],
            compatibilityEnabled: profile.remoteClientCompatibilityEnabled
        ) {
            headers += "Accept: \(accept)\r\n"
        }
        headers += "User-Agent: MCP Controller\r\n"
        headers += "Content-Length: \(request.body.count)\r\n"
        headers += "Connection: close\r\n\r\n"
        var data = Data(headers.utf8)
        data.append(request.body)
        return data
    }

    private func upstreamExcludedHeaders(for request: HTTPRequest) -> Set<String> {
        var excluded: Set<String> = [
            "accept",
            "authorization",
            "connection",
            "content-length",
            "host",
            "keep-alive",
            "mcp-protocol-version",
            "origin",
            "proxy-authenticate",
            "proxy-authorization",
            "proxy-connection",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
            "x-forwarded-host",
            "x-forwarded-prefix",
            "x-forwarded-proto"
        ]
        if let connectionHeader = request.headers["connection"] {
            let namedHopByHopHeaders = connectionHeader
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            excluded.formUnion(namedHopByHopHeaders)
        }
        return excluded
    }

    private func pipeUpstreamResponse(
        _ upstream: NWConnection,
        to client: NWConnection,
        initializeBridge: GatewayInitializeResponseBridge? = nil,
        bufferedDataAfterResponse: Data = Data(),
        upstreamResponseBuffer: Data = Data(),
        deadline: GatewayRequestDeadline
    ) {
        guard !deadline.finished else { upstream.cancel(); return }
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                upstream.cancel()
                client.cancel()
                return
            }
            guard !deadline.finished else { upstream.cancel(); return }

            var combinedBuffer = upstreamResponseBuffer
            if let data, !data.isEmpty { combinedBuffer.append(data) }

            let streamEnded = isComplete || error != nil
            var outgoing: Data?
            var responseComplete = false
            if let data, !data.isEmpty {
                if let initializeBridge {
                    let result = initializeBridge.consume(data, isFinal: streamEnded)
                    outgoing = result?.data
                    responseComplete = result?.responseComplete == true
                    if let sessionID = result?.sessionID {
                        if let upstreamVersion = result?.upstreamVersion {
                            self.bridgedProtocolVersions[sessionID] = upstreamVersion
                            self.logHandler("Protocol bridge active: client=\(initializeBridge.requestedVersion), upstream=\(upstreamVersion), session=\(sessionID.prefix(8))….\n")
                        }
                        if let capabilities = result?.upstreamCapabilities {
                            self.upstreamCapabilities[sessionID] = capabilities
                        }
                    }
                } else {
                    outgoing = data
                    responseComplete = HTTPResponseFraming.isComplete(combinedBuffer, closed: streamEnded)
                }
            } else if let initializeBridge, streamEnded {
                let result = initializeBridge.finish()
                outgoing = result?.data
                responseComplete = result?.responseComplete == true
            }

            let closeAfterResponse = responseComplete
            if (closeAfterResponse || streamEnded), !deadline.claim() {
                upstream.cancel()
                return
            }
            let responseBuffer = combinedBuffer
            if let outgoing, !outgoing.isEmpty {
                deadline.markResponseStarted()
                client.send(content: outgoing, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        _ = deadline.claim()
                        upstream.cancel()
                        client.cancel()
                    } else if closeAfterResponse || streamEnded {
                        upstream.cancel()
                        self.continueReceiving(on: client, bufferedData: bufferedDataAfterResponse)
                    } else {
                        self.pipeUpstreamResponse(
                            upstream,
                            to: client,
                            initializeBridge: initializeBridge,
                            bufferedDataAfterResponse: bufferedDataAfterResponse,
                            upstreamResponseBuffer: responseBuffer,
                            deadline: deadline
                        )
                    }
                })
            } else if streamEnded {
                upstream.cancel()
                self.continueReceiving(on: client, bufferedData: bufferedDataAfterResponse)
            } else {
                self.pipeUpstreamResponse(
                    upstream,
                    to: client,
                    initializeBridge: initializeBridge,
                    bufferedDataAfterResponse: bufferedDataAfterResponse,
                    upstreamResponseBuffer: combinedBuffer,
                    deadline: deadline
                )
            }
        }
    }

    private func sendHeadOK(_ connection: NWConnection, bufferedData: Data = Data()) {
        let response = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nAllow: GET, HEAD, POST, DELETE, OPTIONS\r\nCache-Control: no-store\r\n\r\n".utf8
        )
        send(connection, data: response, keepConnectionOpen: true, bufferedData: bufferedData)
    }

    private func sendPreflightOK(
        _ connection: NWConnection,
        origin: String?,
        requestedHeaders: String?,
        bufferedData: Data = Data()
    ) {
        let allowOrigin = origin ?? "null"
        let allowHeaders = requestedHeaders?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? requestedHeaders!
            : "authorization, content-type, mcp-session-id, mcp-protocol-version"
        let response = Data((
            "HTTP/1.1 204 No Content\r\n" +
            "Content-Length: 0\r\n" +
            "Allow: GET, HEAD, POST, DELETE, OPTIONS\r\n" +
            "Access-Control-Allow-Origin: \(allowOrigin)\r\n" +
            "Access-Control-Allow-Methods: GET, HEAD, POST, DELETE, OPTIONS\r\n" +
            "Access-Control-Allow-Headers: \(allowHeaders)\r\n" +
            "Access-Control-Max-Age: 600\r\n" +
            "Vary: Origin, Access-Control-Request-Headers\r\n\r\n"
        ).utf8)
        send(connection, data: response, keepConnectionOpen: true, bufferedData: bufferedData)
    }

    private func sendCompatibilityResult(
        _ connection: NWConnection,
        requestID: Any,
        sessionID: String?,
        protocolVersion: String?,
        result: [String: Any],
        keepConnectionOpen: Bool = false,
        bufferedData: Data = Data()
    ) {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "result": result]
        let jsonData = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        let jsonText = String(decoding: jsonData, as: UTF8.self)
        let baseMillis = Int(Date().timeIntervalSince1970 * 1000)
        let preludeID = "\(UUID().uuidString)_\(baseMillis)_0000_evt"
        let messageID = "\(UUID().uuidString)_\(baseMillis)_0000_msg"
        let sseText = "id: \(preludeID)\ndata: \n\nevent: message\nid: \(messageID)\ndata: \(jsonText)\n\n"
        var encodedBody = HTTPChunkedBodyEncoder.encode(Data(sseText.utf8))
        encodedBody.append(Data("0\r\n\r\n".utf8))

        var headerLines = [
            "HTTP/1.1 200 OK",
            "Cache-Control: no-cache",
            "Content-Type: text/event-stream",
            "Transfer-Encoding: chunked"
        ]
        if let sessionID, !sessionID.isEmpty {
            headerLines.append("Mcp-Session-Id: \(sessionID)")
        }

        let headers = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(encodedBody)
        send(connection, data: response, keepConnectionOpen: keepConnectionOpen, bufferedData: bufferedData)
    }

    private func sendAccepted(_ connection: NWConnection, keepConnectionOpen: Bool = false, bufferedData: Data = Data()) {
        let response = Data("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\n\r\n".utf8)
        send(connection, data: response, keepConnectionOpen: keepConnectionOpen, bufferedData: bufferedData)
    }

    private func drainUpstreamResponse(_ upstream: NWConnection) {
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
            upstream.cancel()
        }
        queue.asyncAfter(deadline: .now() + 5) { upstream.cancel() }
    }

    private func sendError(
        _ connection: NWConnection,
        status: Int,
        message: String,
        requestID: Any,
        data: [String: Any]? = nil,
        keepConnectionOpen: Bool = false,
        bufferedData: Data = Data()
    ) {
        var errorObject: [String: Any] = ["code": -32001, "message": message]
        if let data { errorObject["data"] = data }
        let object: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "error": errorObject]
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        let headers = "HTTP/1.1 \(status) \(HTTPStatus.reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        send(connection, data: response, keepConnectionOpen: keepConnectionOpen, bufferedData: bufferedData)
    }

    private func send(_ connection: NWConnection, data: Data, keepConnectionOpen: Bool = false, bufferedData: Data = Data()) {
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            if keepConnectionOpen {
                self.continueReceiving(on: connection, bufferedData: bufferedData)
            } else {
                connection.cancel()
            }
        })
    }

    private func publishState() {
        stateHandler(arbiter.active, arbiter.pending.sorted { $0.requestedAt < $1.requestedAt })
    }
}

enum GatewayRequestDeadlinePolicy {
    static func applies(to method: String) -> Bool {
        method.uppercased() != "GET"
    }
}

enum GatewayRequestMethodPolicy {
    static func accepts(_ method: String, remoteClientCompatibilityEnabled: Bool) -> Bool {
        switch method.uppercased() {
        case "POST", "GET", "DELETE", "OPTIONS":
            true
        case "HEAD":
            remoteClientCompatibilityEnabled
        default:
            false
        }
    }
}

enum GatewayRouteMapper {
    static func publicTarget(
        for requestTarget: String,
        forwardedPrefix: String? = nil,
        profile: ServerProfile
    ) -> String {
        let pieces = requestTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = pieces.isEmpty ? "/" : String(pieces[0])
        let query = pieces.count > 1 ? "?" + String(pieces[1]) : ""

        if let forwardedPrefix {
            let firstPrefix = forwardedPrefix.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = firstPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
                let normalizedPrefix = prefixed.count > 1 && prefixed.hasSuffix("/") ? String(prefixed.dropLast()) : prefixed
                if path == "/" { return normalizedPrefix + query }
                if path == normalizedPrefix || path.hasPrefix(normalizedPrefix + "/") { return path + query }
            }
        }

        let mount = profile.normalizedMountPath
        if path == "/" || path == mount { return mount + query }
        return path + query
    }

    static func upstreamTarget(for requestTarget: String, profile: ServerProfile) -> String {
        let mount = profile.normalizedMountPath
        let endpoint = profile.streamableHTTPPath ?? "/"

        if requestTarget == "/" || requestTarget == mount {
            return endpoint
        }
        if mount != "/" {
            let prefix = mount + "/"
            if requestTarget.hasPrefix(prefix) {
                let stripped = String(requestTarget.dropFirst(mount.count))
                return stripped.isEmpty ? endpoint : stripped
            }
        }
        return requestTarget
    }
}

private struct HTTPRequestParseResult {
    let request: HTTPRequest
    let bytesConsumed: Int
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

    var requestIDDescription: String {
        let requestID = jsonRPCID
        if requestID is NSNull { return "none" }
        return String(describing: requestID)
    }

    var requestedProtocolVersion: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] as? String == "initialize",
              let params = object["params"] as? [String: Any] else { return nil }
        return params["protocolVersion"] as? String
    }

    var jsonRPCMethod: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return object["method"] as? String
    }

    var cancellationTargetDescription: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] as? String == "notifications/cancelled",
              let params = object["params"] as? [String: Any] else { return nil }
        if let requestID = params["requestId"] {
            return String(describing: requestID)
        }
        return "unknown"
    }

    var isJSONRPCNotification: Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] is String else { return false }
        return object["id"] == nil
    }

    static func parse(_ data: Data) -> HTTPRequestParseResult? {
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
        let bodyStart = headerRange.upperBound
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            let encodedBody = data.subdata(in: bodyStart..<data.endIndex)
            guard let decoded = HTTPChunkedBodyDecoder.decodeWithConsumed(encodedBody) else { return nil }
            let request = HTTPRequest(method: String(requestParts[0]).uppercased(), target: String(requestParts[1]), headers: headers, body: decoded.body)
            return HTTPRequestParseResult(request: request, bytesConsumed: bodyStart + decoded.bytesConsumed)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        let request = HTTPRequest(method: String(requestParts[0]).uppercased(), target: String(requestParts[1]), headers: headers, body: body)
        return HTTPRequestParseResult(request: request, bytesConsumed: bodyStart + length)
    }
}

private enum HTTPResponseFraming {
    static func isComplete(_ data: Data, closed: Bool = false) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator), let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return false
        }
        let bodyStart = headerRange.upperBound
        let headers = headerText.components(separatedBy: "\r\n")
        var transferEncoding: String?
        var contentLength: Int?
        var connectionHeader: String?
        for line in headers.dropFirst() {
            guard let split = line.firstIndex(of: ":") else { continue }
            let name = line[..<split].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
            if name == "transfer-encoding" { transferEncoding = value.lowercased() }
            if name == "content-length" { contentLength = Int(value) }
            if name == "connection" { connectionHeader = value.lowercased() }
        }
        if transferEncoding?.contains("chunked") == true {
            let encodedBody = data.subdata(in: bodyStart..<data.endIndex)
            guard let decoded = HTTPChunkedBodyDecoder.decodeWithConsumed(encodedBody) else { return false }
            return encodedBody.count >= decoded.bytesConsumed
        }
        if let contentLength { return data.count >= bodyStart + contentLength }
        if closed { return true }
        return connectionHeader?.contains("close") == true && closed
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
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Content Too Large"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
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
