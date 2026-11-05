import SwiftUI
import Combine
import Carbon.HIToolbox

@main
struct LecternApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Lectern", id: "editor") {
            EditorView()
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("Lectern", systemImage: "text.alignleft") {
            MenuContent()
        }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var overlay = OverlayController.shared
    @ObservedObject private var engine = ScrollEngine.shared
    @ObservedObject private var assistant = Assistant.shared

    var body: some View {
        Button("Open Editor") {
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(overlay.isVisible ? "Hide Prompter" : "Show Prompter") { overlay.toggle() }
        Button(engine.isPlaying || engine.countdown != nil ? "Pause" : "Play") {
            overlay.show()
            engine.toggle()
        }
        Button("Restart") { engine.restart() }
        Button(assistant.isListening ? "Stop and Generate Script" : "Dictate to Claude") {
            assistant.toggle()
        }

        Divider()

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Lectern") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Wires the pieces together once the app has launched.
final class AppModel {
    static let shared = AppModel()
    private var bag = Set<AnyCancellable>()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        OverlayController.shared.start()
        registerHotKeys()

        // The microphone is only open while the script is actually playing with voice-follow on.
        ScrollEngine.shared.$isPlaying
            .combineLatest(Preferences.shared.$voiceFollow, Preferences.shared.$wordTracking)
            .receive(on: DispatchQueue.main)
            .sink { playing, follow, words in
                let active = playing && follow
                SpeechFollower.shared.setWanted(active && words)
                if active {
                    VoiceMonitor.shared.acquire("level")    // volume meter and fallback scrolling
                } else {
                    VoiceMonitor.shared.release("level")
                }
            }
            .store(in: &bag)
    }

    private func registerHotKeys() {
        let mods = controlKey | optionKey
        let hk = HotKeyCenter.shared
        let engine = ScrollEngine.shared

        hk.register(keyCode: kVK_Space, modifiers: mods) { engine.toggle() }
        hk.register(keyCode: kVK_UpArrow, modifiers: mods) { engine.changeSpeed(10) }
        hk.register(keyCode: kVK_DownArrow, modifiers: mods) { engine.changeSpeed(-10) }
        hk.register(keyCode: kVK_ANSI_RightBracket, modifiers: mods) { engine.changeSpeed(10) }   // ⌃⌥ ]
        hk.register(keyCode: kVK_ANSI_LeftBracket, modifiers: mods) { engine.changeSpeed(-10) }   // ⌃⌥ [
        hk.register(keyCode: kVK_RightArrow, modifiers: mods) { engine.nextCue() }
        hk.register(keyCode: kVK_LeftArrow, modifiers: mods) { engine.prevCue() }
        hk.register(keyCode: kVK_ANSI_R, modifiers: mods) { engine.restart() }
        hk.register(keyCode: kVK_ANSI_P, modifiers: mods) { OverlayController.shared.toggle() }
        hk.register(keyCode: kVK_ANSI_M, modifiers: mods) { Assistant.shared.toggle() }
        hk.register(keyCode: kVK_ANSI_Equal, modifiers: mods) { engine.changeFontSize(2) }
        hk.register(keyCode: kVK_ANSI_Minus, modifiers: mods) { engine.changeFontSize(-2) }
    }
}
