import SwiftUI
import Combine
import AppKit

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, model }

    let id = UUID()
    let role: Role
    let text: String
    var failed = false
}

enum ChatError: LocalizedError {
    case busy

    var errorDescription: String? {
        "Still working on the last question. Try again in a moment."
    }
}

/// The conversation, shared by the typed chat and the mic button, so the AI remembers earlier turns.
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isBusy = false
    @Published private(set) var error: String?

    private init() {}

    /// Call on the main thread. The completion runs on the main thread.
    func send(_ text: String, system: String, completion: ((Result<String, Error>) -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isBusy else {
            completion?(.failure(ChatError.busy))
            return
        }

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        isBusy = true
        error = nil

        // Failed messages are not part of the conversation the AI sees. Keep the last 24 turns.
        let history = messages
            .filter { !$0.failed }
            .suffix(24)
            .map { AIClient.Message(isUser: $0.role == .user, text: $0.text) }

        let prefs = Preferences.shared
        let provider = prefs.provider
        let model = provider == .gemini ? prefs.geminiModel : prefs.claudeModel

        Task {
            do {
                let reply = try await AIClient.complete(provider: provider, model: model, system: system, messages: Array(history))
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage(role: .model, text: reply))
                    self.isBusy = false
                    completion?(.success(reply))
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    if let i = self.messages.firstIndex(where: { $0.id == userMessage.id }) {
                        self.messages[i].failed = true
                    }
                    self.error = message
                    self.isBusy = false
                    completion?(.failure(error))
                }
            }
        }
    }

    func clear() {
        messages = []
        error = nil
    }
}

/// A normal chat window: type a question, read the answer, and send any answer to the prompter.
struct ChatView: View {
    @ObservedObject private var chat = ChatStore.shared
    @ObservedObject private var assistant = Assistant.shared
    @ObservedObject private var prefs = Preferences.shared

    @State private var input = ""

    private var modelName: String {
        prefs.provider == .gemini ? prefs.geminiModel : prefs.claudeModel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            Text("Ask anything, or click the mic and speak. The conversation is remembered, and you can send any answer to the prompter.")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                            bubble(message, index: index)
                                .id(message.id)
                        }
                        if chat.isBusy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…").foregroundColor(.secondary)
                            }
                            .id("busy")
                        }
                        if let error = chat.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.callout)
                                .id("error")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: chat.isBusy) { _, busy in
                    if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } }
                }
            }

            Divider()
            inputBar
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
            Text("\(prefs.provider.shortName) · \(modelName)")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear chat") { chat.clear() }
                .buttonStyle(.borderless)
                .disabled(chat.messages.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask anything…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit { send() }

            Button {
                assistant.toggle()
            } label: {
                Image(systemName: assistant.isListening ? "stop.circle.fill" : "mic.fill")
                    .foregroundColor(assistant.isListening ? .red : .primary)
            }
            .buttonStyle(.borderless)
            .help("Speak your question. The answer goes to the prompter too.")

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isBusy)
        }
        .padding(10)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage, index: Int) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.failed ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .model:
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 14) {
                    Button {
                        Assistant.shared.present(message.text, title: questionBefore(index))
                    } label: {
                        Label("Read in prompter", systemImage: "text.alignleft")
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.trailing, 60)
        }
    }

    /// The question that led to the answer at this position, used to title the cue.
    private func questionBefore(_ index: Int) -> String {
        var i = index - 1
        while i >= 0 {
            if chat.messages[i].role == .user { return chat.messages[i].text }
            i -= 1
        }
        return "Answer"
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isBusy else { return }
        input = ""
        chat.send(text, system: DefaultText.chatPrompt)
    }
}
