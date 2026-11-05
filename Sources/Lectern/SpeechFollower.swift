import Foundation
import Combine
import Speech
import AVFoundation
import AppKit

// MARK: - Script words

struct IndexedWord {
    let cue: Int
    let range: NSRange        // UTF-16 range inside the cue body
    let norm: String          // lower-case letters and digits only
}

/// Every word of the script in reading order, so spoken words can be matched to a place in the text.
struct ScriptIndex {
    var words: [IndexedWord] = []
    var cueStart: [Int] = []  // index of the first word of each cue

    static func build(from cues: [Cue]) -> ScriptIndex {
        var index = ScriptIndex()
        for cue in cues {
            index.cueStart.append(index.words.count)
            let body = cue.body
            body.enumerateSubstrings(
                in: body.startIndex..<body.endIndex,
                options: [.byWords, .localized]
            ) { substring, range, _, _ in
                guard let substring = substring else { return }
                let norm = WordMatch.normalize(substring)
                guard !norm.isEmpty else { return }
                index.words.append(IndexedWord(cue: cue.id, range: NSRange(range, in: body), norm: norm))
            }
        }
        return index
    }
}

// MARK: - Fuzzy matching

enum WordMatch {
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var out = ""
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            out.append(Character(scalar))
        }
        return out
    }

    /// Equal, or close enough that a speech recogniser could have produced one for the other.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shortest = min(a.count, b.count)
        if shortest < 3 { return false }
        if shortest >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
        if max(a.count, b.count) < 5 { return false }
        return withinOneEdit(Array(a), Array(b))
    }

    private static func withinOneEdit(_ a: [Character], _ b: [Character]) -> Bool {
        if a == b { return true }
        if abs(a.count - b.count) > 1 { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                i += 1; j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count {
                i += 1
            } else if b.count > a.count {
                j += 1
            } else {
                i += 1; j += 1
            }
        }
        edits += (a.count - i) + (b.count - j)
        return edits <= 1
    }

    /// Finds where in the script the last few spoken words belong.
    /// Returns the number of script words that have now been spoken, or nil if nothing matches well.
    static func locate(tail: [String], words: [IndexedWord], current: Int) -> Int? {
        let n = tail.count
        guard n > 0, !words.isEmpty else { return nil }

        let lo = max(0, current - 8)
        let hi = min(words.count - 1, current + 60)
        guard lo <= hi else { return nil }

        let last = tail[n - 1]
        var best: (end: Int, score: Int, cost: Int)? = nil

        for e in lo...hi {
            guard similar(last, words[e].norm) else { continue }

            // How many of the recent spoken words line up with the script words ending here?
            var score = 1
            var j = 1
            while j < n && e - j >= 0 {
                if similar(tail[n - 1 - j], words[e - j].norm) { score += 1 }
                j += 1
            }

            let newPos = e + 1
            if newPos < current && score < 3 { continue }                 // going back needs strong evidence
            if newPos > current + 12 && score < 3 { continue }            // so does a big jump forward
            if score < 2 && !(n == 1 && newPos >= current && newPos <= current + 3) { continue }

            let cost = abs(newPos - (current + 1))                        // prefer the next expected word
            if let b = best {
                if score > b.score || (score == b.score && cost < b.cost) {
                    best = (e, score, cost)
                }
            } else {
                best = (e, score, cost)
            }
        }
        return best.map { $0.end + 1 }
    }
}

// MARK: - Line positions

/// Works out where a given word sits vertically inside a cue, using the same font and width as the prompter.
enum TextProbe {
    private struct Entry {
        let key: String
        let storage: NSTextStorage
        let layout: NSLayoutManager
        let container: NSTextContainer
    }

    private static var cache: [Int: Entry] = [:]

    static func lineTop(cueID: Int, body: String, range: NSRange, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let length = (body as NSString).length
        guard length > 0 else { return 0 }

        let key = "\(body.hashValue)|\(Int(fontSize))|\(Int(width))"
        let entry: Entry
        if let cached = cache[cueID], cached.key == key {
            entry = cached
        } else {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineSpacing = fontSize * 0.25
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .paragraphStyle: style,
            ]
            let storage = NSTextStorage(string: body, attributes: attributes)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: max(40, width), height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            entry = Entry(key: key, storage: storage, layout: layout, container: container)
            cache[cueID] = entry
        }

        let location = min(range.location, length - 1)
        let glyphRange = entry.layout.glyphRange(
            forCharacterRange: NSRange(location: location, length: 1),
            actualCharacterRange: nil
        )
        let rect = entry.layout.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        return rect.minY
    }
}

// MARK: - Speech follower

/// Listens while you read, matches your words to the script, and reports how far you have got.
/// The prompter scrolls to that spot, and stops when you stop.
final class SpeechFollower: ObservableObject {
    static let shared = SpeechFollower()

    /// Number of script words that have been spoken so far.
    @Published private(set) var position = 0
    /// True while speech recognition is live. When false the prompter falls back to volume-based scrolling.
    @Published private(set) var isTracking = false
    @Published private(set) var heardRecently = false
    @Published private(set) var problem: String?

    private(set) var index = ScriptIndex()

    private var wanted = false
    private var suspended = false
    private var gaveUp = false
    private var useServer = false          // false = on-device only; set after repeated failures
    private var failures = 0
    private var sessionStart = Date()
    private var generation = 0             // identifies the current recognition session
    private var lastTranscript = ""
    private var quietTimer: Timer?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var bag = Set<AnyCancellable>()

    private init() {
        ScriptStore.shared.$cues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in self?.rebuild(cues) }
            .store(in: &bag)
    }

    // MARK: Control

    func setWanted(_ value: Bool) {
        if value && !wanted {
            gaveUp = false
            failures = 0
            problem = nil
        }
        wanted = value
        refresh()
    }

    /// Paused while another feature (dictation) needs the recogniser.
    func setSuspended(_ value: Bool) {
        suspended = value
        refresh()
    }

    func reset() {
        setPosition(0)
    }

    func setPosition(_ newValue: Int) {
        let clamped = max(0, min(newValue, index.words.count))
        if clamped != position { position = clamped }
        ScrollEngine.shared.followPositionChanged()
    }

    /// UTF-16 offset inside a cue body up to which the words have been spoken.
    func spokenOffset(forCue cueID: Int, bodyLength: Int) -> Int {
        guard cueID < index.cueStart.count else { return 0 }
        let start = index.cueStart[cueID]
        let end = cueID + 1 < index.cueStart.count ? index.cueStart[cueID + 1] : index.words.count
        if position <= start { return 0 }
        if position >= end { return bodyLength }
        let r = index.words[position - 1].range
        return r.location + r.length
    }

    // MARK: Index

    private func rebuild(_ cues: [Cue]) {
        index = ScriptIndex.build(from: cues)
        if position > index.words.count { position = index.words.count }
        ScrollEngine.shared.followPositionChanged()
    }

    // MARK: Session lifecycle

    private func refresh() {
        let shouldRun = wanted && !suspended && !gaveUp
        if shouldRun && task == nil {
            start()
        } else if !shouldRun && (task != nil || isTracking) {
            stop()
        }
    }

    private func start() {
        VoiceMonitor.shared.requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.problem = "Microphone access is off."
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard status == .authorized else {
                        self.problem = "Speech Recognition access is off."
                        return
                    }
                    guard self.wanted, !self.suspended, !self.gaveUp, self.task == nil else { return }
                    self.beginSession()
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            problem = "Speech recognition isn't available."
            giveUp()
            return
        }
        self.recognizer = recognizer

        generation += 1
        let gen = generation
        sessionStart = Date()
        lastTranscript = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition && !useServer {
            req.requiresOnDeviceRecognition = true
        }
        req.contextualStrings = contextWords()
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handle(result: result, error: error, generation: gen)
            }
        }

        VoiceMonitor.shared.setSink("follow") { [weak req] buffer in req?.append(buffer) }
        VoiceMonitor.shared.acquire("follow")
        isTracking = true
        problem = nil
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation gen: Int) {
        guard gen == generation else { return }     // a late callback from a finished session

        if let result = result {
            let text = result.bestTranscription.formattedString
            if !text.isEmpty { failures = 0 }
            if text != lastTranscript {
                lastTranscript = text
                markHeard()
                advance(using: text)
            }
            if result.isFinal {
                endSession(failed: false)
                return
            }
        }
        if error != nil {
            endSession(failed: true)
        }
    }

    /// Recognition sessions end on their own now and then. Start a fresh one straight away.
    private func endSession(failed: Bool) {
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        VoiceMonitor.shared.setSink("follow", nil)

        if failed {
            if Date().timeIntervalSince(sessionStart) < 2 {
                failures += 1
            } else {
                failures = 0
            }
            if failures == 2 { useServer = true }       // on-device model may be missing; use Apple's servers
            if failures >= 4 {
                problem = "Speech tracking isn't working here."
                giveUp()
                return
            }
        }

        guard wanted, !suspended else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, self.wanted, !self.suspended, !self.gaveUp, self.task == nil else { return }
            self.beginSession()
        }
    }

    private func giveUp() {
        gaveUp = true
        stop()
    }

    private func stop() {
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        VoiceMonitor.shared.setSink("follow", nil)
        VoiceMonitor.shared.release("follow")
        quietTimer?.invalidate()
        isTracking = false
        heardRecently = false
    }

    // MARK: Matching

    private func advance(using text: String) {
        let spoken = text
            .split(separator: " ")
            .map { WordMatch.normalize(String($0)) }
            .filter { !$0.isEmpty }
        guard !spoken.isEmpty, !index.words.isEmpty else { return }

        let tail = Array(spoken.suffix(6))
        guard let newPosition = WordMatch.locate(tail: tail, words: index.words, current: position),
              newPosition != position else { return }

        position = newPosition
        ScrollEngine.shared.followPositionChanged()
    }

    private func markHeard() {
        heardRecently = true
        quietTimer?.invalidate()
        quietTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.heardRecently = false
        }
    }

    /// Hints to the recogniser: the unusual words from your script.
    private func contextWords() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for cue in ScriptStore.shared.cues {
            let pieces = cue.body.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            for piece in pieces {
                let word = String(piece)
                if word.count >= 5, seen.insert(word.lowercased()).inserted {
                    out.append(word)
                    if out.count >= 100 { return out }
                }
            }
        }
        return out
    }
}
