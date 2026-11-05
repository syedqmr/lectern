import Foundation
import Combine
import Speech
import AVFoundation

/// The mic button. Records what you say (a question, a request, or rough notes), transcribes it,
/// asks Gemini or Claude, and appends the answer to your script as a new cue. The prompter opens on it
/// and starts, so you can read the answer straight away.
///
/// Speech is transcribed with Apple's recognizer (on-device when the Mac supports it).
/// Only the resulting text is sent to the AI service.
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
    private var capturing = false

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

        // The script tracker and the dictation button can't both use the recogniser at once.
        SpeechFollower.shared.setSuspended(true)

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

        VoiceMonitor.shared.setSink("assistant") { [weak req] buffer in req?.append(buffer) }
        VoiceMonitor.shared.acquire("assistant")
        capturing = true
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
        guard capturing else { return }
        capturing = false
        VoiceMonitor.shared.setSink("assistant", nil)
        VoiceMonitor.shared.release("assistant")
        SpeechFollower.shared.setSuspended(false)
    }

    // MARK: Asking the AI

    private func sendIfNeeded() {
        guard !sent else { return }
        sent = true

        task?.cancel()
        task = nil
        request = nil
        stopCapture()

        let prompt = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            fail("I didn't catch anything. Tap the mic and try again.")
            return
        }

        phase = .thinking
        // Goes through the shared conversation, so the chat tab shows it and the AI remembers it.
        ChatStore.shared.send(prompt, system: Preferences.shared.systemPrompt) { [weak self] result in
            switch result {
            case .success(let reply):
                self?.phase = .idle
                self?.present(reply, title: prompt)
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self?.fail(message)
            }
        }
    }

    /// Adds an answer to the script, opens the prompter on it, and starts reading if that is enabled.
    func present(_ reply: String, title prompt: String) {
        let words = prompt.split(separator: " ").prefix(5).joined(separator: " ")
        ScriptStore.shared.appendCue(title: "AI · \(words)", body: reply)

        // Give the prompter a moment to lay out the new cue, then bring it up, park on it, and start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let engine = ScrollEngine.shared
            let target = max(0, ScriptStore.shared.cues.count - 1)
            OverlayController.shared.show()
            engine.pause()
            engine.jump(toCue: target)

            if Preferences.shared.autoPlayAnswers && Preferences.shared.voiceFollow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    engine.play()
                }
            }
        }
    }

    private func fail(_ message: String) {
        stopCapture()
        phase = .failed(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self = self else { return }
            if case .failed = self.phase { self.phase = .idle }
        }
    }
}
