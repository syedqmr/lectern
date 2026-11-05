import SwiftUI

enum PrompterMode: String, CaseIterable, Identifiable {
    case notch
    case floating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notch: return "Notch (under the camera)"
        case .floating: return "Floating window"
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini
    case claude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini: return "Google AI Studio (Gemini)"
        case .claude: return "Anthropic (Claude)"
        }
    }

    var shortName: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    var keyName: String {
        switch self {
        case .gemini: return "Google AI Studio API key"
        case .claude: return "Anthropic API key"
        }
    }
}

enum DefaultText {
    static let systemPrompt = """
    You write text that will be read aloud from a teleprompter. The user speaks a question, a request, or rough notes. \
    If it is a question or a request, answer it directly in natural spoken language, as if the user were saying the answer \
    themselves to an audience. If they give rough notes or a draft, rewrite it as a polished spoken script that keeps their meaning. \
    Use short sentences. No markdown, no bullet points, no headings, no stage directions, and no preamble such as "Sure" or "Here is". \
    Keep it under about 200 words unless they ask for more.
    """

    static let script = """
    ## Opening
    Hi, I'm glad you're here. Today I want to show you something that makes talking to a camera feel a lot more natural.

    ## The idea
    Your notes sit right under the lens, so you can read while still looking at the person on the other side.

    ## Wrap up
    Start a new section any time with two hash marks and a title. Jump between sections from the controls, or with the keyboard.
    """
}

/// All user-facing settings. Values are persisted to UserDefaults as they change.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    // Display
    @Published var mode: PrompterMode { didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") } }
    @Published var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") } }
    @Published var textColorHex: String { didSet { UserDefaults.standard.set(textColorHex, forKey: "textColorHex") } }
    @Published var mirror: Bool { didSet { UserDefaults.standard.set(mirror, forKey: "mirror") } }
    @Published var notchWidth: Double { didSet { UserDefaults.standard.set(notchWidth, forKey: "notchWidth") } }
    @Published var notchHeight: Double { didSet { UserDefaults.standard.set(notchHeight, forKey: "notchHeight") } }
    @Published var overlayVisible: Bool { didSet { UserDefaults.standard.set(overlayVisible, forKey: "overlayVisible") } }

    // Scrolling
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "speed") } }
    @Published var voiceFollow: Bool { didSet { UserDefaults.standard.set(voiceFollow, forKey: "voiceFollow") } }
    @Published var voiceThreshold: Double { didSet { UserDefaults.standard.set(voiceThreshold, forKey: "voiceThreshold") } }
    @Published var pauseOnHover: Bool { didSet { UserDefaults.standard.set(pauseOnHover, forKey: "pauseOnHover") } }
    @Published var countdown: Int { didSet { UserDefaults.standard.set(countdown, forKey: "countdown") } }

    // Privacy
    @Published var hideFromCapture: Bool { didSet { UserDefaults.standard.set(hideFromCapture, forKey: "hideFromCapture") } }

    // AI assistant
    @Published var provider: AIProvider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") } }
    @Published var geminiModel: String { didSet { UserDefaults.standard.set(geminiModel, forKey: "geminiModel") } }
    @Published var claudeModel: String { didSet { UserDefaults.standard.set(claudeModel, forKey: "model") } }
    @Published var autoPlayAnswers: Bool { didSet { UserDefaults.standard.set(autoPlayAnswers, forKey: "autoPlayAnswers") } }
    @Published var systemPrompt: String { didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "mode": PrompterMode.notch.rawValue,
            "fontSize": 30.0,
            "textColorHex": "#FFFFFF",
            "mirror": false,
            "notchWidth": 460.0,
            "notchHeight": 150.0,
            "overlayVisible": true,
            "speed": 45.0,
            "voiceFollow": true,
            "voiceThreshold": 0.35,
            "pauseOnHover": true,
            "countdown": 3,
            "hideFromCapture": true,
            "provider": AIProvider.gemini.rawValue,
            "geminiModel": "gemini-3.8-flash",
            "model": "claude-sonnet-5-5",
            "autoPlayAnswers": true,
            "systemPrompt": DefaultText.systemPrompt,
        ])

        mode = PrompterMode(rawValue: d.string(forKey: "mode") ?? "") ?? .notch
        fontSize = d.double(forKey: "fontSize")
        textColorHex = d.string(forKey: "textColorHex") ?? "#FFFFFF"
        mirror = d.bool(forKey: "mirror")
        notchWidth = d.double(forKey: "notchWidth")
        notchHeight = d.double(forKey: "notchHeight")
        overlayVisible = d.bool(forKey: "overlayVisible")
        speed = d.double(forKey: "speed")
        voiceFollow = d.bool(forKey: "voiceFollow")
        voiceThreshold = d.double(forKey: "voiceThreshold")
        pauseOnHover = d.bool(forKey: "pauseOnHover")
        countdown = d.integer(forKey: "countdown")
        hideFromCapture = d.bool(forKey: "hideFromCapture")
        provider = AIProvider(rawValue: d.string(forKey: "provider") ?? "") ?? .gemini
        geminiModel = d.string(forKey: "geminiModel") ?? "gemini-3.8-flash"
        claudeModel = d.string(forKey: "model") ?? "claude-sonnet-5-5"
        autoPlayAnswers = d.bool(forKey: "autoPlayAnswers")
        systemPrompt = d.string(forKey: "systemPrompt") ?? DefaultText.systemPrompt
    }
}
