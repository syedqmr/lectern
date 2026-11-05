import SwiftUI

private struct CueTopsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct BodyFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
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
    @ObservedObject private var follower = SpeechFollower.shared
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
        .onChange(of: prefs.fontSize) { _, _ in
            // Layout settles a moment after the size changes; then re-aim at the current word.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                engine.followPositionChanged()
            }
        }
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
        .onPreferenceChange(BodyFramesKey.self) { frames in
            DispatchQueue.main.async {
                engine.bodyFrames = frames
                engine.followPositionChanged()
            }
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
            bodyText(cue)
                .font(.system(size: prefs.fontSize, weight: .semibold))
                .lineSpacing(prefs.fontSize * 0.25)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(
                            key: BodyFramesKey.self,
                            value: [cue.id: g.frame(in: .named("scroller"))]
                        )
                    }
                )
        }
    }

    /// The cue's text, with the words you have already said dimmed.
    private func bodyText(_ cue: Cue) -> Text {
        let full = textColor
        let dim = textColor.opacity(0.35)

        guard prefs.voiceFollow, follower.isTracking, follower.position > 0 else {
            return Text(cue.body).foregroundColor(full)
        }

        let ns = cue.body as NSString
        let cut = min(max(follower.spokenOffset(forCue: cue.id, bodyLength: ns.length), 0), ns.length)

        if cut <= 0 {
            return Text(cue.body).foregroundColor(full)
        }
        if cut >= ns.length {
            return Text(cue.body).foregroundColor(dim)
        }
        return Text(ns.substring(to: cut)).foregroundColor(dim)
            + Text(ns.substring(from: cut)).foregroundColor(full)
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
            guard prefs.voiceFollow, engine.isPlaying, engine.countdown == nil, !engine.isHovering else { return nil }
            if follower.isTracking {
                return follower.heardRecently ? nil : "Listening… start reading"
            }
            if let problem = follower.problem {
                return problem + " Scrolling by volume instead."
            }
            if voice.permissionDenied {
                return "Microphone access is off. Enable it in System Settings."
            }
            if voice.isRunning && !voice.speaking {
                return "Waiting for your voice…"
            }
            return nil
        case .listening:
            let t = assistant.transcript
            return t.isEmpty ? "Listening… tap the mic when you're done" : String(t.suffix(90))
        case .thinking:
            return "Writing your answer…"
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
        HStack(spacing: 4) {
            iconButton("backward.end.fill") { engine.prevCue() }
            iconButton(engine.isPlaying || engine.countdown != nil ? "pause.fill" : "play.fill") { engine.toggle() }
            iconButton("forward.end.fill") { engine.nextCue() }

            Divider().frame(height: 14)

            // Text size
            iconButton("textformat.size.smaller") { engine.changeFontSize(-2) }
            Text("\(Int(prefs.fontSize))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(minWidth: 22)
            iconButton("textformat.size.larger") { engine.changeFontSize(2) }

            Divider().frame(height: 14)

            // Speed
            iconButton("tortoise.fill") { engine.changeSpeed(-5) }
            Text("\(Int(prefs.speed))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(minWidth: 26)
            iconButton("hare.fill") { engine.changeSpeed(5) }

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
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
