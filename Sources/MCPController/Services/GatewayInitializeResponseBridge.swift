import Foundation

struct GatewayInitializeBridgeOutput {
    let data: Data
    let sessionID: String?
    let upstreamVersion: String?
    let upstreamCapabilities: Set<String>?
    let responseComplete: Bool
}

final class GatewayInitializeResponseBridge: @unchecked Sendable {
    let requestedVersion: String
    private var buffer = Data()
    private var resolved = false

    init(requestedVersion: String) { self.requestedVersion = requestedVersion }

    func consume(_ data: Data, isFinal: Bool = false) -> GatewayInitializeBridgeOutput? {
        if resolved { return .init(data: data, sessionID: nil, upstreamVersion: nil, upstreamCapabilities: nil, responseComplete: false) }
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
                return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream, capabilities: transformed.capabilities, responseComplete: true)
            }
            if let raw = transform(buffer) {
                return resolve(raw.body, sessionID: sessionID(in: headerText), upstream: raw.upstream, capabilities: raw.capabilities, responseComplete: false)
            }
            return isFinal || buffer.count > 1_048_576 ? finish() : nil
        }

        if let length = contentLength(in: headerText), encodedBody.count < length { return isFinal ? finish() : nil }
        if let transformed = transform(encodedBody) {
            var output = header; output.append(transformed.body)
            return resolve(output, sessionID: sessionID(in: headerText), upstream: transformed.upstream, capabilities: transformed.capabilities, responseComplete: true)
        }
        return isFinal || buffer.count > 1_048_576 ? finish() : nil
    }

    func finish() -> GatewayInitializeBridgeOutput? {
        guard !buffer.isEmpty else { return nil }
        resolved = true; let output = buffer; buffer.removeAll()
        return .init(data: output, sessionID: nil, upstreamVersion: nil, upstreamCapabilities: nil, responseComplete: true)
    }

    private func resolve(
        _ data: Data,
        sessionID: String?,
        upstream: String?,
        capabilities: Set<String>?,
        responseComplete: Bool
    ) -> GatewayInitializeBridgeOutput {
        resolved = true; buffer.removeAll()
        return .init(data: data, sessionID: sessionID, upstreamVersion: upstream, upstreamCapabilities: capabilities, responseComplete: responseComplete)
    }

    private func transform(_ data: Data) -> (body: Data, upstream: String, capabilities: Set<String>?)? {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        let normalized = injectCompatibilityCapabilities(into: text)
        text = normalized.text
        let capabilities = normalized.capabilities
        let regex = try! NSRegularExpression(pattern: #"\"protocolVersion\"\s*:\s*\"([^\"]+)\""#)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: full), let versionRange = Range(match.range(at: 1), in: text) else { return nil }
        let upstream = String(text[versionRange])
        text.replaceSubrange(versionRange, with: requestedVersion)
        return (Data(text.utf8), upstream, capabilities)
    }

    private func injectCompatibilityCapabilities(into text: String) -> (text: String, capabilities: Set<String>?) {
        let regex = try! NSRegularExpression(pattern: #"(?m)^data:\s*(\{.*\})\r?$"#)
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, range: full),
           let jsonRange = Range(match.range(at: 1), in: text),
           let normalized = normalizeInitializePayloadJSON(String(text[jsonRange])) {
            var updated = text
            updated.replaceSubrange(jsonRange, with: normalized.json)
            return (updated, normalized.capabilities)
        }
        if let normalized = normalizeInitializePayloadJSON(text) {
            return (normalized.json, normalized.capabilities)
        }
        return (text, extractCapabilities(from: text))
    }

    private func normalizeInitializePayloadJSON(_ jsonText: String) -> (json: String, capabilities: Set<String>)? {
        guard let data = jsonText.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var result = object["result"] as? [String: Any],
              result["protocolVersion"] is String else { return nil }
        var capabilities = result["capabilities"] as? [String: Any] ?? [:]
        if capabilities["prompts"] == nil { capabilities["prompts"] = [:] }
        if capabilities["resources"] == nil { capabilities["resources"] = [:] }
        result["capabilities"] = capabilities
        object["result"] = result
        guard let normalizedData = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return (String(decoding: normalizedData, as: UTF8.self), Set(capabilities.keys))
    }

    private func extractCapabilities(from text: String) -> Set<String>? {
        var candidates = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { return nil }
            return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        candidates.append(text)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = object["result"] as? [String: Any],
                  let capabilities = result["capabilities"] as? [String: Any] else { continue }
            return Set(capabilities.keys)
        }
        return nil
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
