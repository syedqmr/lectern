import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var voice = VoiceMonitor.shared
    @ObservedObject private var follower = SpeechFollower.shared

    @State private var geminiKey = ""
    @State private var claudeKey = ""
    @State private var testingMic = false

    var body: some View {
        TabView {
            displayTab
                .tabItem { Label("Display", systemImage: "textformat.size") }
            voiceTab
                .tabItem { Label("Voice", systemImage: "waveform") }
            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 540, height: 520)
        .onDisappear {
            if testingMic {
                voice.release("settings-test")
                testingMic = false
            }
        }
    }

    // MARK: Display

    private var displayTab: some View {
        Form {
            Section("Prompter") {
                Picker("Position", selection: $prefs.mode) {
                    ForEach(PrompterMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $prefs.fontSize, in: 16...96, step: 1)
                        Text("\(Int(prefs.fontSize))").monospacedDigit().frame(width: 28)
                    }
                }

                ColorPicker(
                    "Text color",
                    selection: Binding(
                        get: { Color(hex: prefs.textColorHex) },
                        set: { prefs.textColorHex = $0.hexString }
                    ),
                    supportsOpacity: false
                )

                Toggle("Mirror text (for glass teleprompters)", isOn: $prefs.mirror)
            }

            if prefs.mode == .notch {
                Section("Notch size") {
                    LabeledContent("Width") {
                        HStack {
                            Slider(value: $prefs.notchWidth, in: 300...900, step: 10)
                            Text("\(Int(prefs.notchWidth))").monospacedDigit().frame(width: 36)
                        }
                    }
                    LabeledContent("Height below camera") {
                        HStack {
                            Slider(value: $prefs.notchHeight, in: 80...400, step: 5)
                            Text("\(Int(prefs.notchHeight))").monospacedDigit().frame(width: 36)
                        }
                    }
                }
            } else {
                Section {
                    Text("Drag the prompter anywhere and resize it from its edges.")
                        .foregroundColor(.secondary)
                }
            }

            Section("Privacy") {
                Toggle("Hide the prompter from screen sharing and screenshots", isOn: $prefs.hideFromCapture)
                Text("Test this with the app you present in. Some capture methods on newer macOS versions may still show it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Voice

    private var voiceTab: some View {
        Form {
            Section("Scrolling") {
                Toggle("Scroll while I speak, pause when I stop", isOn: $prefs.voiceFollow)
                Text("The text moves while the microphone hears your voice and stops when you go quiet. Tune the threshold below if it reacts to background noise or misses your voice.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $prefs.speed, in: 10...200, step: 5)
                        Text("\(Int(prefs.speed))").monospacedDigit().frame(width: 32)
                    }
                }

                Toggle("Follow my exact words (experimental)", isOn: $prefs.wordTracking)
                    .disabled(!prefs.voiceFollow)
                Text("Matches what you say to the script and scrolls to your place. It needs clear speech recognition and can get stuck if it mishears you, so it's off by default.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Pause while the pointer is over the prompter", isOn: $prefs.pauseOnHover)
                Stepper(prefs.countdown == 0 ? "Countdown: off (starts immediately)" : "Countdown: \(prefs.countdown) s",
                        value: $prefs.countdown, in: 0...10)
            }

            Section("Microphone") {
                LabeledContent("Volume threshold") {
                    Slider(value: $prefs.voiceThreshold, in: 0.1...0.8)
                }
                LabeledContent("Level") {
                    ProgressView(value: voice.level)
                        .tint(voice.speaking ? .green : .secondary)
                }
                Button(testingMic ? "Stop test" : "Test microphone") {
                    if testingMic {
                        voice.release("settings-test")
                    } else {
                        voice.acquire("settings-test")
                    }
                    testingMic.toggle()
                }
                Text("The threshold is only used for the volume-based fallback and the level bar. Speak normally while testing; the bar turns green when you talk.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if voice.permissionDenied {
                    Text("Microphone access is off. Enable Lectern in System Settings → Privacy & Security → Microphone.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if let problem = follower.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: AI

    private var aiTab: some View {
        Form {
            Section("Answer engine") {
                Picker("Use", selection: $prefs.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                Toggle("Start reading an answer as soon as it appears", isOn: $prefs.autoPlayAnswers)
                Text("Click the mic, ask a question or say some rough notes, click again. The answer is added to your script and shown in the prompter. Only the text of what you said is sent. Your voice never leaves your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Google AI Studio (Gemini)") {
                SecureField("API key", text: $geminiKey)
                    .onChange(of: geminiKey) { _, newValue in
                        Keychain.set(newValue, for: Keychain.geminiKeyAccount)
                    }
                TextField("Model", text: $prefs.geminiModel)
                Text("Create a free key at aistudio.google.com/apikey. It is stored in your macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Anthropic (Claude)") {
                SecureField("API key", text: $claudeKey)
                    .onChange(of: claudeKey) { _, newValue in
                        Keychain.set(newValue, for: Keychain.apiKeyAccount)
                    }
                TextField("Model", text: $prefs.claudeModel)
            }

            Section("Instructions for the AI") {
                TextEditor(text: $prefs.systemPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 100)
                Button("Reset to default") {
                    prefs.systemPrompt = DefaultText.systemPrompt
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            geminiKey = Keychain.get(Keychain.geminiKeyAccount) ?? ""
            claudeKey = Keychain.get(Keychain.apiKeyAccount) ?? ""
        }
    }

    // MARK: Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section("Global shortcuts (work in any app)") {
                shortcutRow("Play / pause", "⌃⌥ Space")
                shortcutRow("Faster / slower", "⌃⌥ ↑  /  ⌃⌥ ↓")
                shortcutRow("Faster / slower (alternative)", "⌃⌥ ]  /  ⌃⌥ [")
                shortcutRow("Bigger / smaller text", "⌃⌥ =  /  ⌃⌥ -")
                shortcutRow("Next / previous cue", "⌃⌥ →  /  ⌃⌥ ←")
                shortcutRow("Restart from the top", "⌃⌥ R")
                shortcutRow("Show / hide prompter", "⌃⌥ P")
                shortcutRow("Mic: ask a question", "⌃⌥ M")
            }
            Section {
                Text("You can also scroll over the prompter with the trackpad, or hover to pause and show the size and speed buttons.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys).font(.system(.body, design: .monospaced))
        }
    }
}
