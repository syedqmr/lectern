import SwiftUI

private struct CueTopsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The text that appears under the camera.
struct PrompterView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var store = ScriptStore.shared
    @ObservedObject private var engine = ScrollEngine.shared
    @ObservedObject private var voice = VoiceMonitor.shared
    @ObservedObject private var assistant = Assistant.shared
    @ObservedObject private var layout = OverlayLayout.shared

    private var textColor: Color { Color(hex: prefs.textColorHex) }
    private var isNotch: Bool { prefs.mode == .notch }

    private var panelShape: AnyShape {
        if isNotch {
            return AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Color.clear.frame(height: layout.topInset)
                viewport
            }

            if let n = engine.countdown {
                countdownOverlay(n)
            }
            if prefs.voiceFollow && voice.isRunning {
                beam
            }
            if engine.isHovering {
                controls
            }
        }
        .overlay(alignment: .top) {
            if let text = statusText {
                statusPill(text)
                    .padding(.top, layout.topInset + 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(isNotch ? 1 : 0.9))
        .clipShape(panelShape)
    }

    // MARK: Scrolling text

    private var viewport: some View {
        GeometryReader { geo in
            scroller(in: geo)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.10),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .scaleEffect(x: prefs.mirror ? -1 : 1, y: 1)
    }

    private func scroller(in geo: GeometryProxy) -> some View {
        VStack(spacing: 26) {
            ForEach(store.cues) { cue in
                cueBlock(cue)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: CueTopsKey.self,
                                value: [cue.id: g.frame(in: .named("scroller")).minY]
                            )
                        }
                    )
            }
            // Lets the last lines scroll up toward the camera.
            Color.clear.frame(height: geo.size.height * 0.7)
        }
        .padding(.horizontal, 22)
        .frame(width: geo.size.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
            }
        )
        .coordinateSpace(name: "scroller")
        .offset(y: -CGFloat(engine.offset))
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        .clipped()
        .onPreferenceChange(CueTopsKey.self) { tops in
            DispatchQueue.main.async { engine.cueTops = tops }
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            DispatchQueue.main.async { engine.contentHeight = Double(h) }
        }
        .onAppear { engine.viewportHeight = Double(geo.size.height) }
        .onChange(of: geo.size.height) { _, newValue in
            engine.viewportHeight = Double(newValue)
        }
    }

    private func cueBlock(_ cue: Cue) -> some View {
        VStack(spacing: 8) {
            if store.cues.count > 1 {
                Text(cue.title.uppercased())
                    .font(.system(size: max(10, prefs.fontSize * 0.36), weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(textColor.opacity(0.45))
            }
            Text(cue.body)
                .font(.system(size: prefs.fontSize, weight: .semibold))
                .foregroundColor(textColor)
                .lineSpacing(prefs.fontSize * 0.25)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Overlays

    private func countdownOverlay(_ n: Int) -> some View {
        ZStack {
            Color.black.opacity(0.7)
            Text("\(n)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.top, layout.topInset)
        .allowsHitTesting(false)
    }

    /// A thin bar along the bottom edge that follows your voice level.
    private var beam: some View {
        Rectangle()
            .fill(voice.speaking ? Color.green : Color.white.opacity(0.35))
            .frame(height: 3)
            .scaleEffect(x: CGFloat(max(0.03, voice.level)), y: 1)
            .allowsHitTesting(false)
    }

    private var statusText: String? {
        switch assistant.phase {
        case .idle:
            if prefs.voiceFollow && engine.isPlaying && engine.countdown == nil
                && voice.isRunning && !voice.speaking && !engine.isHovering {
                return "Waiting for your voice…"
            }
            if voice.permissionDenied && prefs.voiceFollow && engine.isPlaying {
                return "Microphone access is off. Enable it in System Settings."
            }
            return nil
        case .listening:
            let t = assistant.transcript
            return t.isEmpty ? "Listening… tap the mic when you're done" : String(t.suffix(90))
        case .thinking:
            return "Writing your script…"
        case .failed(let message):
            return message
        }
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.14), in: Capsule())
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
    }

    // MARK: Controls (shown while the pointer is over the prompter)

    private var controls: some View {
        HStack(spacing: 6) {
            iconButton("backward.end.fill") { engine.prevCue() }
            iconButton(engine.isPlaying || engine.countdown != nil ? "pause.fill" : "play.fill") { engine.toggle() }
            iconButton("forward.end.fill") { engine.nextCue() }

            Divider().frame(height: 14)

            iconButton("minus") { engine.changeSpeed(-5) }
            Text("\(Int(prefs.speed))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(minWidth: 26)
            iconButton("plus") { engine.changeSpeed(5) }

            Divider().frame(height: 14)

            iconButton(micIcon, tint: micTint) { assistant.toggle() }
            iconButton("xmark") { OverlayController.shared.hide() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(.bottom, 8)
    }

    private var micIcon: String {
        switch assistant.phase {
        case .listening: return "stop.circle.fill"
        case .thinking: return "ellipsis.circle"
        default: return "mic.fill"
        }
    }

    private var micTint: Color {
        assistant.phase == .listening ? .red : .white
    }

    private func iconButton(_ name: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
