import Foundation

/// Verifies that a listening wrapper can actually initialize its MCP child.
enum MCPReadinessProbe {
    static func verify(profile: ServerProfile) async throws {
        guard let path = profile.streamableHTTPPath, !path.isEmpty else { return }
        guard let url = URL(string: "http://127.0.0.1:\(profile.localPort)\(path)") else {
            throw ProbeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = Data("""
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"mcp-controller-readiness","version":"1.0"}}}
        """.utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProbeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProbeError.httpStatus(http.statusCode)
        }
    }

    enum ProbeError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "The MCP endpoint URL is invalid."
            case .invalidResponse: "The MCP endpoint returned a non-HTTP response."
            case .httpStatus(let status): "The MCP endpoint returned HTTP \(status)."
            }
        }
    }
}
