import Foundation

struct GatewayInitializeBridgeOutput {
    let data: Data
    let sessionID: String?
    let upstreamVersion: String?
}

final class GatewayInitializeResponseBridge: @unchecked Sendable {
    private let requestedVersion: String
    private var buffer = Data()
    private var resolved = false

    init(requestedVersion: String) {
        self.requestedVersion = requestedVersion
    }

    func consume(_ data: Data, isFinal: Bool = false) -> GatewayInitializeBridgeOutput? {
        if resolved { return GatewayInitializeBridgeOutput(data: data, sessionID: nil, upstreamVersion: nil) }
        buffer.append(data)

        let prefix = Data("\"protocolVersion\":\"".utf8)
        guard let versionPrefix = buffer.range(of: prefix) else {
            if isFinal || buffer.count > 1_048_576 { return finish() }
            return nil
        }
        let versionStart = versionPrefix.upperBound
        guard let quote = buffer[versionStart...].firstIndex(of: UInt8(ascii: "\"")) else {
            if isFinal { return finish() }
            return nil
        }
        let upstreamVersion = String(data: buffer[versionStart..<quote], encoding: .utf8)
        let sessionID = Self.sessionID(in: buffer)

        if let upstreamVersion, requestedVersion.utf8.count == upstreamVersion.utf8.count {
            buffer.replaceSubrange(versionStart..<quote, with: requestedVersion.utf8)
        }
        resolved = true
        let output = buffer
        buffer.removeAll(keepingCapacity: false)
        return GatewayInitializeBridgeOutput(data: output, sessionID: sessionID, upstreamVersion: upstreamVersion)
    }

    func finish() -> GatewayInitializeBridgeOutput? {
        guard !buffer.isEmpty else { return nil }
        resolved = true
        let output = buffer
        buffer.removeAll(keepingCapacity: false)
        return GatewayInitializeBridgeOutput(data: output, sessionID: nil, upstreamVersion: nil)
    }

    private static func sessionID(in response: Data) -> String? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = response.range(of: separator),
              let headerText = String(data: response[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        for line in headerText.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name == "mcp-session-id" {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
