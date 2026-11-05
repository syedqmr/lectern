import Foundation

enum AIError: LocalizedError {
    case noKey(AIProvider)
    case http(AIProvider, Int, String)
    case blocked(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey(let provider):
            return "Add your \(provider.keyName) in Settings → AI."
        case .http(let provider, let code, let message):
            return "\(provider.shortName) error \(code): \(message)"
        case .blocked(let reason):
            return "The answer was blocked (\(reason)). Try rephrasing."
        case .badResponse:
            return "The AI returned a response I couldn't read."
        }
    }
}

/// Talks to Google AI Studio (Gemini) or Anthropic (Claude). Only text is sent.
enum AIClient {
    static func apiKey(for provider: AIProvider) -> String {
        let env = ProcessInfo.processInfo.environment
        switch provider {
        case .gemini:
            if let k = Keychain.get(Keychain.geminiKeyAccount), !k.isEmpty { return k }
            return env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"] ?? ""
        case .claude:
            if let k = Keychain.get(Keychain.apiKeyAccount), !k.isEmpty { return k }
            return env["ANTHROPIC_API_KEY"] ?? ""
        }
    }

    /// One turn of a conversation.
    struct Message {
        let isUser: Bool
        let text: String
    }

    static func complete(provider: AIProvider, model: String, system: String, prompt: String) async throws -> String {
        try await complete(provider: provider, model: model, system: system, messages: [Message(isUser: true, text: prompt)])
    }

    /// Sends the whole conversation so far, so the AI remembers earlier turns.
    static func complete(provider: AIProvider, model: String, system: String, messages: [Message]) async throws -> String {
        switch provider {
        case .gemini: return try await gemini(model: model, system: system, messages: messages)
        case .claude: return try await claude(model: model, system: system, messages: messages)
        }
    }

    // MARK: Gemini (Google AI Studio)

    private static func gemini(model: String, system: String, messages: [Message]) async throws -> String {
        let key = apiKey(for: .gemini)
        guard !key.isEmpty else { throw AIError.noKey(.gemini) }

        var name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("models/") { name.removeFirst("models/".count) }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent") else {
            throw AIError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents = messages.map { m -> [String: Any] in
            ["role": m.isUser ? "user" : "model", "parts": [["text": m.text]]]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data, provider: .gemini)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.badResponse
        }

        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            var text = ""
            for part in parts {
                if let thought = part["thought"] as? Bool, thought { continue }   // skip reasoning summaries
                if let t = part["text"] as? String { text += t }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let feedback = json["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String {
            throw AIError.blocked(reason)
        }
        throw AIError.badResponse
    }

    // MARK: Claude (Anthropic)

    private static func claude(model: String, system: String, messages: [Message]) async throws -> String {
        let key = apiKey(for: .claude)
        guard !key.isEmpty else { throw AIError.noKey(.claude) }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let turns = messages.map { m -> [String: Any] in
            ["role": m.isUser ? "user" : "assistant", "content": m.text]
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": system,
            "messages": turns,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data, provider: .claude)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw AIError.badResponse
        }

        var text = ""
        for block in blocks {
            if let type = block["type"] as? String, type == "text", let t = block["text"] as? String {
                text += t
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.badResponse }
        return trimmed
    }

    // MARK: Shared

    private static func check(_ response: URLResponse, _ data: Data, provider: AIProvider) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(provider, http.statusCode, errorMessage(from: data))
        }
    }

    /// Pulls "error.message" out of an API error body, or falls back to the raw text.
    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(240))
        }
        return String((String(data: data, encoding: .utf8) ?? "").prefix(240))
    }
}
