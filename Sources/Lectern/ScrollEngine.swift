import Foundation
import SwiftUI

/// Drives the prompter: playback, countdown, easing, cue jumps.
/// Everything here runs on the main thread.
final class ScrollEngine: ObservableObject {
    static let shared = ScrollEngine()

    @Published var offset: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var countdown: Int? = nil
    @Published var isHovering = false
    @Published private(set) var currentCue = 0

    // Measured by the prompter view.
    var cueTops: [Int: CGFloat] = [:]
    var contentHeight: Double = 0
    var viewportHeight: Double = 0

    private var timer: Timer?
    private var countdownTimer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var ramp = 0.0              // eases scrolling in and out when the voice starts and stops
    private var jumpTarget: Double?

    private init() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var maxOffset: Double {
        max(0, contentHeight - viewportHeight)
    }

    // MARK: Playback

    func toggle() {
        if countdown != nil {
            cancelCountdown()
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !isPlaying, countdown == nil else { return }
        let seconds = Preferences.shared.countdown
        if seconds > 0 && offset < 1 {
            countdown = seconds
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] t in self?.countdownTick(t) }
            RunLoop.main.add(t, forMode: .common)
            countdownTimer = t
        } else {
            isPlaying = true
        }
    }

    func pause() {
        cancelCountdown()
        isPlaying = false
    }

    func restart() {
        pause()
        jumpTarget = nil
        ramp = 0
        offset = 0
        currentCue = 0
    }

    func changeSpeed(_ delta: Double) {
        let p = Preferences.shared
        p.speed = min(200, max(10, p.speed + delta))
    }

    /// Manual scroll, e.g. from the trackpad.
    func nudge(_ delta: Double) {
        jumpTarget = nil
        offset = min(max(0, offset + delta), maxOffset)
        updateCurrentCue()
    }

    // MARK: Cues

    func jump(toCue index: Int) {
        guard let top = cueTops[index] else { return }
        jumpTarget = min(max(0, Double(top) - 4), maxOffset)
    }

    func nextCue() {
        let last = max(0, cueTops.count - 1)
        jump(toCue: min(currentCue + 1, last))
    }

    func prevCue() {
        let start = Double(cueTops[currentCue] ?? 0)
        if offset - start > 80 {
            jump(toCue: currentCue)
        } else {
            jump(toCue: max(currentCue - 1, 0))
        }
    }

    // MARK: Internals

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if countdown != nil { countdown = nil }
    }

    private func countdownTick(_ t: Timer) {
        guard let c = countdown else {
            t.invalidate()
            return
        }
        if c <= 1 {
            t.invalidate()
            countdownTimer = nil
            countdown = nil
            isPlaying = true
        } else {
            countdown = c - 1
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        // Animated jump to a cue.
        if let target = jumpTarget {
            let diff = target - offset
            if abs(diff) < 0.5 {
                offset = target
                jumpTarget = nil
            } else {
                offset += diff * min(1, dt * 12)
            }
            updateCurrentCue()
            return
        }

        let prefs = Preferences.shared
        var target = 0.0
        if isPlaying && countdown == nil && !(prefs.pauseOnHover && isHovering) {
            target = (!prefs.voiceFollow || VoiceMonitor.shared.speaking) ? 1 : 0
        }
        ramp += (target - ramp) * min(1, dt * 10)
        if target == 0 && ramp < 0.02 { ramp = 0 }

        guard ramp > 0 else { return }

        let limit = maxOffset
        let next = offset + prefs.speed * ramp * dt
        if limit > 0 && next >= limit {
            offset = limit
            pause()                      // reached the end of the script
        } else {
            offset = next
        }
        updateCurrentCue()
    }

    private func updateCurrentCue() {
        let probe = CGFloat(offset + 12)
        var index = 0
        for (i, top) in cueTops where top <= probe && i > index {
            index = i
        }
        if index != currentCue { currentCue = index }
    }
}
