import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var voice = VoiceMonitor.shared

    @State private var apiKey = ""
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
        .frame(width: 520, height: 440)
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
                        Slider(value: $prefs.fontSize, in: 16...72, step: 1)
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
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $prefs.speed, in: 10...200, step: 5)
                        Text("\(Int(prefs.speed))").monospacedDigit().frame(width: 32)
                    }
                }
                Toggle("Follow my voice (scroll while I speak, pause when I stop)", isOn: $prefs.voiceFollow)
                Toggle("Pause while the pointer is over the prompter", isOn: $prefs.pauseOnHover)
                Stepper("Countdown: \(prefs.countdown) s", value: $prefs.countdown, in: 0...10)
            }

            Section("Microphone sensitivity") {
                LabeledContent("Threshold") {
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
                Text("Speak normally while testing. The bar should turn green when you talk and stay grey in background noise. Headphones help.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if voice.permissionDenied {
                    Text("Microphone access is off. Enable Lectern in System Settings → Privacy & Security → Microphone.")
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
            Section("Anthropic API") {
                SecureField("API key", text: $apiKey)
                    .onAppear { apiKey = Keychain.get(Keychain.apiKeyAccount) ?? "" }
                    .onChange(of: apiKey) { _, newValue in
                        Keychain.set(newValue, for: Keychain.apiKeyAccount)
                    }
                TextField("Model", text: $prefs.model)
                Text("The key is stored in your macOS Keychain. When you use the mic button, only the text of what you said is sent to the Anthropic API. Audio stays on your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Instructions for Claude") {
                TextEditor(text: $prefs.systemPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 110)
                Button("Reset to default") {
                    prefs.systemPrompt = DefaultText.systemPrompt
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section("Global shortcuts (work in any app)") {
                shortcutRow("Play / pause", "⌃⌥ Space")
                shortcutRow("Faster / slower", "⌃⌥ ↑  /  ⌃⌥ ↓")
                shortcutRow("Next / previous cue", "⌃⌥ →  /  ⌃⌥ ←")
                shortcutRow("Restart from the top", "⌃⌥ R")
                shortcutRow("Show / hide prompter", "⌃⌥ P")
                shortcutRow("Dictate to Claude", "⌃⌥ M")
            }
            Section {
                Text("You can also scroll over the prompter with the trackpad, or hover to pause.")
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
