import Foundation
import Combine

/// A section of the script. In the editor a section starts with a line like "## Title".
struct Cue: Identifiable, Equatable {
    let id: Int          // position in the script
    var title: String
    var body: String

    static func parse(_ text: String) -> [Cue] {
        var cues: [Cue] = []
        var title: String? = nil
        var buffer: [String] = []

        func flush() {
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if title != nil || !body.isEmpty {
                cues.append(Cue(id: cues.count, title: title ?? "Intro", body: body))
            }
            title = nil
            buffer = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                buffer.append(line)
            }
        }
        flush()

        if cues.isEmpty {
            cues = [Cue(id: 0, title: "Intro", body: "")]
        }
        return cues
    }
}

/// Holds the script text and its parsed cues. Everything stays on this Mac.
final class ScriptStore: ObservableObject {
    static let shared = ScriptStore()

    @Published var text: String {
        didSet {
            UserDefaults.standard.set(text, forKey: "scriptText")
            cues = Cue.parse(text)
        }
    }
    @Published private(set) var cues: [Cue]

    private init() {
        let saved = UserDefaults.standard.string(forKey: "scriptText") ?? DefaultText.script
        text = saved
        cues = Cue.parse(saved)
    }

    /// Adds a new section at the end of the script.
    func appendCue(title: String, body: String) {
        let cleanTitle = title.replacingOccurrences(of: "\n", with: " ")
        // A body line that begins with "## " would split the section, so flatten it.
        let cleanBody = body
            .components(separatedBy: "\n")
            .map { $0.hasPrefix("## ") ? String($0.dropFirst(3)) : $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var separator = ""
        if !text.isEmpty {
            if text.hasSuffix("\n\n") {
                separator = ""
            } else if text.hasSuffix("\n") {
                separator = "\n"
            } else {
                separator = "\n\n"
            }
        }
        text += separator + "## \(cleanTitle)\n\(cleanBody)\n"
    }
}
