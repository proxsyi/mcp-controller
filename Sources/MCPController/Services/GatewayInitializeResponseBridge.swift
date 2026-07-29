import Foundation

struct GatewayInitializeBridgeOutput {
    let data: Data
    let sessionID: String?
    let upstreamVersion: String?
}

final class GatewayInitializeResponseBridge: @unchecked Sendable {
    let requestedVersion: String
    private var buffer = Data()
    private var resolved = false

    init(requestedVersion: String) { self.requestedVersion = requestedVersion }

    func consume(_ data: Data, isFinal: Bool = false) -> GatewayInitializeBridgeOutput? {
        if resolved { return .init(data: data, sessionID: nil, upstreamVersion: nil) }
        buffer.append(data)
        let separator = Data("\r\n\r\n".utf8)
        guard let split = buffer.range(of: separator) else { return isFinal ? finish() : nil }
        let headerEnd = split.upperBound
        let header = buffer.subdata(in: 0..<headerEnd)
        let encodedBody = buffer.subdata(in: headerEnd..<buffer.count)
        let headerText = String(decoding: header, as: UTF8.self)
        let lowered = headerText.lowercased()

        if lowered.contains("transfer-encoding: chunked") {
            if let body = HTTPChunkedBodyDecoder.decode(encodedBody), let transformed = transform(body) {
                var output = header
                output.append(HTTPChunkedBodyEncoder.encode(transformed.body))
                output.append(Data("0\r\n\r\n".utf8))
                return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream)
            }
            if let raw = transform(buffer) {
                return resolve(raw.body, sessionID: sessionID(in: headerText), upstream: raw.upstream)
            }
            return isFinal || buffer.count > 1_048_576 ? finish() : nil
        }

        if let length = contentLength(in: headerText), encodedBody.count < length { return isFinal ? finish() : nil }
        if let transformed = transform(encodedBody) {
            var output = header; output.append(transformed.body)
            return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream)
        }
        return isFinal || buffer.count > 1_048_576 ? finish() : nil
    }

    func finish() -> GatewayInitializeBridgeOutput? {
        guard !buffer.isEmpty else { return nil }
        resolved = true; let output = buffer; buffer.removeAll()
        return .init(data: output, sessionID: nil, upstreamVersion: nil)
    }

    private func resolve(_ data: Data, sessionID: String?, upstream: String?) -> GatewayInitializeBridgeOutput {
        resolved = true; buffer.removeAll()
        return .init(data: data, sessionID: sessionID, upstreamVersion: upstream)
    }

    private func transform(_ data: Data) -> (body: Data, upstream: String)? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        let regex = try! NSRegularExpression(pattern: #"\"protocolVersion\"\s*:\s*\"([^\"]+)\""#)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: full), let versionRange = Range(match.range(at: 1), in: text) else { return nil }
        let upstream = String(text[versionRange])
        text.replaceSubrange(versionRange, with: requestedVersion)
        return (Data(text.utf8), upstream)
    }

    private func sessionID(in headers: String) -> String? {
        for line in headers.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "mcp-session-id" {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func contentLength(in headers: String) -> Int? {
        for line in headers.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
