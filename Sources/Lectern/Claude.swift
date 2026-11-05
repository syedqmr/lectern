import Foundation

enum ClaudeError: LocalizedError {
    case noKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "Add your Anthropic API key in Settings → AI."
        case .http(let code, let body):
            let snippet = body.prefix(200)
            return "Claude API error \(code): \(snippet)"
        case .badResponse:
            return "Claude returned a response I couldn't read."
        }
    }
}

/// Minimal client for the Anthropic Messages API.
enum ClaudeClient {
    static func apiKey() -> String {
        if let stored = Keychain.get(Keychain.apiKeyAccount), !stored.isEmpty { return stored }
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    static func complete(model: String, system: String, prompt: String) async throws -> String {
        let key = apiKey()
        guard !key.isEmpty else { throw ClaudeError.noKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw ClaudeError.badResponse
        }

        var text = ""
        for block in blocks {
            if let type = block["type"] as? String, type == "text", let t = block["text"] as? String {
                text += t
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeError.badResponse }
        return trimmed
    }
}
