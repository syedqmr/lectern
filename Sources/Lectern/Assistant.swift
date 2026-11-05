import Foundation
import Combine
import Speech
import AVFoundation

/// The mic button. Records what you say, transcribes it, asks Claude for a spoken-style script,
/// and appends the reply to your script as a new cue so you can read it in the prompter.
///
/// Speech is transcribed with Apple's recognizer (on-device when the Mac supports it).
/// Only the resulting text is sent to the Anthropic API.
final class Assistant: ObservableObject {
    static let shared = Assistant()

    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sent = false

    private init() {}

    var isListening: Bool { phase == .listening }

    func toggle() {
        switch phase {
        case .listening: finishListening()
        case .thinking: break
        default: begin()
        }
    }

    // MARK: Listening

    private func begin() {
        VoiceMonitor.shared.requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.fail("Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone.")
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard status == .authorized else {
                        self.fail("Speech Recognition access is off. Turn it on in System Settings → Privacy & Security.")
                        return
                    }
                    self.startListening()
                }
            }
        }
    }

    private func startListening() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }

        transcript = ""
        sent = false
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handle(result: result, error: error)
            }
        }

        VoiceMonitor.shared.bufferSink = { [weak req] buffer in req?.append(buffer) }
        VoiceMonitor.shared.acquire("assistant")
        phase = .listening
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result = result {
            transcript = result.bestTranscription.formattedString
            if result.isFinal { sendIfNeeded() }
        }
        if error != nil {
            // The recognizer gave up (for example, it heard nothing).
            if phase == .listening { finishListening() } else { sendIfNeeded() }
        }
    }

    private func finishListening() {
        guard phase == .listening else { return }
        phase = .thinking
        stopCapture()
        request?.endAudio()
        // Normally the final result arrives right after endAudio. This is a safety net.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.sendIfNeeded()
        }
    }

    private func stopCapture() {
        VoiceMonitor.shared.bufferSink = nil
        VoiceMonitor.shared.release("assistant")
    }

    // MARK: Asking Claude

    private func sendIfNeeded() {
        guard !sent else { return }
        sent = true

        task?.cancel()
        task = nil
        request = nil
        if phase == .listening { stopCapture() }

        let prompt = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            fail("I didn't catch anything. Tap the mic and try again.")
            return
        }

        phase = .thinking
        let model = Preferences.shared.model
        let system = Preferences.shared.systemPrompt

        Task {
            do {
                let reply = try await ClaudeClient.complete(model: model, system: system, prompt: prompt)
                DispatchQueue.main.async { self.deliver(reply, for: prompt) }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async { self.fail(message) }
            }
        }
    }

    private func deliver(_ reply: String, for prompt: String) {
        let words = prompt.split(separator: " ").prefix(5).joined(separator: " ")
        ScriptStore.shared.appendCue(title: "AI · \(words)", body: reply)
        phase = .idle

        // Give the prompter a moment to lay out the new cue, then bring it up and park on it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            OverlayController.shared.show()
            ScrollEngine.shared.pause()
            ScrollEngine.shared.jump(toCue: max(0, ScriptStore.shared.cues.count - 1))
        }
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self = self else { return }
            if case .failed = self.phase { self.phase = .idle }
        }
    }
}
