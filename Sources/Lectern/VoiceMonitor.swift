import Foundation
import Combine
import AVFoundation

/// Listens to the microphone. It measures loudness (for the level beam and as a fallback scroll signal)
/// and hands raw audio buffers to any number of named consumers, such as the speech tracker or the dictation button.
///
/// Several parts of the app may need the mic at once, so callers "acquire" and "release" it by name.
/// The engine runs only while at least one name holds it.
final class VoiceMonitor: ObservableObject {
    static let shared = VoiceMonitor()

    @Published private(set) var level: Double = 0        // 0...1, smoothed loudness
    @Published private(set) var speaking = false
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    private let engine = AVAudioEngine()
    private var holds = Set<String>()
    private var lastLoud = Date.distantPast

    private let sinkLock = NSLock()
    private var sinks: [String: (AVAudioPCMBuffer) -> Void] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.holds.isEmpty else { return }
            self.stopEngine()
            self.startEngineIfNeeded()
        }
    }

    // MARK: Public

    func acquire(_ name: String) {
        holds.insert(name)
        startEngineIfNeeded()
    }

    func release(_ name: String) {
        holds.remove(name)
        if holds.isEmpty { stopEngine() }
    }

    /// Registers (or, with nil, removes) a consumer of raw audio buffers. Called on the audio thread.
    func setSink(_ name: String, _ sink: ((AVAudioPCMBuffer) -> Void)?) {
        sinkLock.lock()
        defer { sinkLock.unlock() }
        sinks[name] = sink
    }

    /// Calls back on the main thread.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    // MARK: Engine

    private func startEngineIfNeeded() {
        guard !isRunning, !holds.isEmpty else { return }
        requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.permissionDenied = true
                return
            }
            self.permissionDenied = false
            // Things may have changed while the permission prompt was open.
            guard !self.isRunning, !self.holds.isEmpty else { return }
            self.beginEngine()
        }
    }

    private func beginEngine() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            NSLog("Lectern: could not start audio engine: \(error)")
        }
    }

    private func stopEngine() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        speaking = false
    }

    /// Runs on the audio thread.
    private func process(_ buffer: AVAudioPCMBuffer) {
        sinkLock.lock()
        let consumers = Array(sinks.values)
        sinkLock.unlock()
        for consumer in consumers { consumer(buffer) }

        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for i in 0..<count {
            let s = channel[i]
            sum += s * s
        }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        let normalised = Double(max(0, min(1, (db + 60) / 60)))   // -60 dB ... 0 dB -> 0 ... 1

        DispatchQueue.main.async { [weak self] in
            self?.ingest(normalised)
        }
    }

    private func ingest(_ value: Double) {
        guard isRunning else { return }
        // Fast attack, slower release.
        level = value > level ? value : level * 0.85 + value * 0.15

        let now = Date()
        if level > Preferences.shared.voiceThreshold {
            lastLoud = now
        }
        let isSpeaking = now.timeIntervalSince(lastLoud) < 0.5
        if isSpeaking != speaking { speaking = isSpeaking }
    }
}
