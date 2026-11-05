# Lectern

A notch teleprompter for macOS, written from scratch in Swift/SwiftUI. It is modelled on the
*publicly described* behaviour of Moody (moodyteleprompter.com): the script sits under your
camera, scrolls while you speak, and stays out of screen shares. It also has a mic button that
turns anything you dictate into a script you can read in the prompter.

No Moody code, assets or branding are used. Moody's internals are not public, so everything here is
an independent implementation of the features it advertises.

> **Status: not compiled yet.** I wrote this in a Linux workspace with no Swift toolchain or macOS
> SDK, so it has been reviewed by reading but never built. Expect to fix a few small compile errors on
> the first build. Paste any errors back and they are usually one-line fixes.

## Build

Requires macOS 14+ and Xcode command-line tools (Swift 5.9+).

```bash
./build.sh
open build/Lectern.app
```

It has to run as a `.app` bundle (the script makes one). A bare binary can't show the microphone and
speech-recognition permission prompts.

## Using it

- **Editor window:** write your script. Start a new section ("cue") with a line like `## Title`.
  Click a cue in the sidebar to jump to it.
- **Prompter:** appears under the camera. Hover to pause and show the controls
  (previous/next cue, play/pause, speed, mic, close).
- **Voice follow:** with it on, text scrolls while you speak and eases to a stop when you pause. Tune
  the threshold in Settings → Voice using the live level bar.
- **Floating mode:** Settings → Display → Position. Drag it anywhere, resize from the edges, mirror
  the text for a glass teleprompter.
- **Hidden from screen share:** on by default (`NSWindow.sharingType = .none`).
- **Trackpad:** scroll over the prompter to move manually.

### Mic button (dictate → script)

1. Add your Anthropic API key in Settings → AI (stored in the Keychain). `ANTHROPIC_API_KEY` in the
   environment also works.
2. Click the mic (editor toolbar, prompter controls, menu bar, or ⌃⌥M), say a prompt or rough notes,
   click again to stop.
3. Apple's speech recognizer transcribes it (on-device when your Mac supports that). The text goes to
   the Claude API and the reply is appended as a new cue, then the prompter opens parked on it.

Edit the instructions Claude gets (Settings → AI) to change what it does with your speech, for
example "answer my question" versus "tidy my rough notes into a script". The default model is
`claude-sonnet-5-5`; change it in the same tab.

**Privacy:** unlike Moody's "nothing leaves your Mac" stance, the mic button sends the *transcribed
text* to Anthropic. Audio is never uploaded. Everything else (script, voice-follow) stays local.

### Global shortcuts

All use ⌃⌥: Space play/pause, ↑/↓ speed, ←/→ cue, R restart, P show/hide, M dictate.

## Things to test first

1. **Screen-share hiding.** `sharingType = .none` is the standard mechanism, but I'm not certain it is
   honoured by every capture path on recent macOS versions (ScreenCaptureKit-based apps in
   particular). Test it with the app you actually present in before relying on it.
2. **Notch placement.** Uses `safeAreaInsets` and the auxiliary top areas to find the camera
   housing. On a Mac without a notch it just docks to the top centre.
3. **Hover pause and clicks** on the non-activating panel.
4. **Settings from the menu bar.** If the Settings window opens behind other windows, use ⌘, from the
   editor instead.
5. **Keychain prompts.** Ad-hoc signing means macOS may ask for Keychain access again after rebuilds.

## Layout

```
Package.swift            SwiftPM manifest (macOS 14)
Resources/Info.plist     bundle info + mic / speech permission strings
build.sh                 builds and wraps the .app, ad-hoc signed
Sources/Lectern/
  LecternApp.swift       app entry, menu bar, hotkey wiring
  OverlayController.swift  notch/floating panel, capture hiding, hover, scroll wheel
  PrompterView.swift     scrolling text, countdown, voice beam, controls
  ScrollEngine.swift     playback, easing, cue jumps, countdown
  VoiceMonitor.swift     mic level -> "speaking" signal; shared with the assistant
  Assistant.swift        mic button: dictate -> transcribe -> Claude -> new cue
  Claude.swift           Messages API client
  ScriptStore.swift      script text and cue parsing
  EditorView.swift       editor window with cue sidebar
  SettingsView.swift     settings tabs
  Preferences.swift      persisted settings
  HotKeys.swift          global shortcuts (Carbon, no Accessibility permission)
  Util.swift             colour, notch geometry, Keychain helpers
```

## Not included (vs. Moody's marketing page)

iPhone remote, screen recording, and a license/payment flow.
