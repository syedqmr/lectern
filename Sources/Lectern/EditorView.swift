import SwiftUI

private enum EditorTab: Hashable {
    case script
    case chat
}

struct EditorView: View {
    @State private var tab: EditorTab = .script
    @ObservedObject private var store = ScriptStore.shared
    @ObservedObject private var engine = ScrollEngine.shared
    @ObservedObject private var assistant = Assistant.shared
    @ObservedObject private var overlay = OverlayController.shared
    @ObservedObject private var prefs = Preferences.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 170, idealWidth: 210, maxWidth: 300)

            VStack(spacing: 0) {
                if tab == .chat {
                    ChatView()
                } else {
                    TextEditor(text: $store.text)
                        .font(.system(size: 15))
                        .padding(10)
                }

                Divider()
                controlsBar
                Divider()
                statusBar
            }
            .frame(minWidth: 380)
        }
        .frame(minWidth: 720, minHeight: 440)
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $tab) {
                    Text("Script").tag(EditorTab.script)
                    Text("Chat").tag(EditorTab.chat)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Button {
                    overlay.toggle()
                } label: {
                    Label(overlay.isVisible ? "Hide Prompter" : "Show Prompter",
                          systemImage: overlay.isVisible ? "eye.slash" : "eye")
                }

                Button {
                    overlay.show()
                    engine.toggle()
                } label: {
                    Label(engine.isPlaying || engine.countdown != nil ? "Pause" : "Play",
                          systemImage: engine.isPlaying || engine.countdown != nil ? "pause.fill" : "play.fill")
                }

                Button {
                    engine.restart()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }

                Button {
                    assistant.toggle()
                } label: {
                    Label(micLabel, systemImage: micIcon)
                }
                .help("Ask a question or dictate notes. The answer appears in the prompter, ready to read.")

                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(store.cues) { cue in
                Button {
                    overlay.show()
                    engine.jump(toCue: cue.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cue.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(cue.body.isEmpty ? "Empty" : String(cue.body.prefix(70)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(engine.currentCue == cue.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                let next = store.cues.count + 1
                store.appendCue(title: "Cue \(next)", body: "")
            } label: {
                Label("Add cue", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: Text size and speed

    private var controlsBar: some View {
        HStack(spacing: 22) {
            HStack(spacing: 8) {
                Image(systemName: "textformat.size")
                Text("Text size")
                Slider(value: $prefs.fontSize, in: 16...96, step: 1)
                    .frame(width: 150)
                Text("\(Int(prefs.fontSize))")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                Text("Speed")
                Slider(value: $prefs.speed, in: 10...200, step: 5)
                    .frame(width: 150)
                Text("\(Int(prefs.speed))")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }

            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch assistant.phase {
            case .idle:
                Image(systemName: "info.circle").foregroundColor(.secondary)
                Text("Start a new cue with a line like “## Title”. Click a cue to jump to it.")
                    .foregroundColor(.secondary)
            case .listening:
                Image(systemName: "waveform").foregroundColor(.red)
                Text(assistant.transcript.isEmpty ? "Listening… click the mic when you're done." : assistant.transcript)
                    .lineLimit(2)
            case .thinking:
                ProgressView().controlSize(.small)
                Text("Writing your script…")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(message).lineLimit(2)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var micIcon: String {
        switch assistant.phase {
        case .listening: return "stop.circle.fill"
        case .thinking: return "ellipsis.circle"
        default: return "mic.fill"
        }
    }

    private var micLabel: String {
        switch assistant.phase {
        case .listening: return "Stop and generate"
        case .thinking: return "Working…"
        default: return "Dictate"
        }
    }
}
