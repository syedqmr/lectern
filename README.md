# Lectern

A notch teleprompter for macOS, written from scratch in Swift/SwiftUI. The script sits under your
camera, follows the words you actually say, and stays out of screen shares. A mic button turns a spoken
question into an answer that appears in the prompter, ready to read.

No code, assets or branding from any other teleprompter are used.

## Download

Every push to `main` builds the app on GitHub's Mac servers. Grab `Lectern-mac.zip` from the
[latest release](../../releases/tag/latest), unzip, and open `Lectern.app`. The first time, macOS will warn
that it can't verify the app (it isn't signed with a paid Apple certificate): open
**System Settings → Privacy & Security → Open Anyway**.

To build it yourself instead: `bash build.sh` on macOS 14+ with Xcode command-line tools.

## Using it

- **Editor window:** write your script. Start a new section ("cue") with a line like `## Title`.
  Click a cue in the sidebar to jump to it. **Text size** and **Speed** sliders are under the text box.
- **Prompter:** appears under the camera. Hover to pause and show the controls
  (previous/next cue, play/pause, text size, speed, mic, close).
- **Follow my words:** press play and start reading. Lectern transcribes your speech, matches it to the
  script (tolerating misheard words and ad-libs), scrolls to your place, dims the words you have said, and
  stops when you stop. If you skip ahead or go back, it re-finds your place. If speech recognition isn't
  available it falls back to scrolling while it hears your voice.
- **Speed:** with Follow on, how quickly the text catches up with you; with it off, how fast it scrolls.
- **Floating mode:** Settings → Display → Position. Drag anywhere, resize from the edges, mirror the text.
- **Hidden from screen share:** on by default (`NSWindow.sharingType = .none`).

### Mic button (ask a question → answer in the prompter)

1. Settings → AI: pick **Google AI Studio (Gemini)** or **Anthropic (Claude)** and paste that provider's API
   key. Get a free Gemini key at aistudio.google.com/apikey. Keys are stored in the macOS Keychain.
2. Click the mic (editor toolbar, prompter controls, menu bar, or ⌃⌥M), ask a question or say rough notes,
   click again.
3. Apple's speech recognizer transcribes it, the text goes to the AI, and the answer is added to your script
   as a new cue. The prompter opens on it and starts, so you can read it aloud right away.

**Privacy:** audio is never uploaded by Lectern. Only the transcribed text goes to the AI provider you chose.
Speech recognition runs on-device when your Mac supports it; if it can't, macOS may use Apple's servers.

### Global shortcuts

All use ⌃⌥: Space play/pause, ↑/↓ speed, =/- text size, ←/→ cue, R restart, P show/hide, M mic.

## Things to check

1. **Screen-share hiding.** Uses the standard window flag; not every capture path on recent macOS honours it.
   Test with the app you present in.
2. **Speech tracking** depends on macOS dictation being able to recognise your language.
3. **Settings from the menu bar** can open behind other windows; the editor's toolbar has a Settings button.

## Layout

```
Package.swift              SwiftPM manifest (macOS 14)
Resources/Info.plist       bundle info + mic / speech permission strings
build.sh                   builds and wraps the .app, ad-hoc signed
.github/workflows/build.yml  builds the app on a Mac runner and publishes the release
Sources/Lectern/
  LecternApp.swift         app entry, menu bar, hotkeys
  OverlayController.swift  notch/floating panel, capture hiding, hover, scroll wheel
  PrompterView.swift       scrolling text, dimming, countdown, controls
  ScrollEngine.swift       playback, easing, cue jumps, following your speech
  SpeechFollower.swift     live recognition, fuzzy word matching, line positions
  VoiceMonitor.swift       shared microphone, volume level
  Assistant.swift          mic button: ask -> transcribe -> AI -> new cue -> read
  AI.swift                 Gemini and Claude clients
  ScriptStore.swift        script text and cue parsing
  EditorView.swift         editor window, cue sidebar, size/speed sliders
  SettingsView.swift       settings tabs
  Preferences.swift        persisted settings
  HotKeys.swift            global shortcuts
  Util.swift               colour, notch geometry, Keychain helpers
```
