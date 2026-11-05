import AppKit
import SwiftUI
import Combine

/// Shared layout facts the SwiftUI prompter needs.
final class OverlayLayout: ObservableObject {
    static let shared = OverlayLayout()
    /// Height of the physical notch. Text starts below this line.
    @Published var topInset: CGFloat = 0
    private init() {}
}

/// Borderless panel that floats above everything, including full-screen apps.
final class PrompterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Stops AppKit from pushing the panel below the menu bar, so it can sit over the notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosts the SwiftUI view and reports mouse enter/exit reliably, even while the app is in the background.
final class TrackingContainer: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    @Published private(set) var isVisible = false

    private var panel: PrompterPanel?
    private var bag = Set<AnyCancellable>()
    private var appliedLayoutKey = ""
    private var scrollMonitor: Any?

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard panel == nil else { return }
        buildPanel()
        applyPrivacy()
        applyLayout(force: true)

        Preferences.shared.objectWillChange
            .receive(on: RunLoop.main)          // run after the new value has been stored
            .sink { [weak self] _ in
                self?.applyPrivacy()
                self?.applyLayout(force: false)
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLayout(force: true) }
            .store(in: &bag)

        // Remember where the floating window was left.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.publisher(for: name, object: panel)
                .sink { [weak self] _ in self?.saveFloatingFrame() }
                .store(in: &bag)
        }

        // Trackpad / mouse-wheel scrolling over the prompter.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let panel = self?.panel, event.window === panel else { return event }
            let scale: Double = event.hasPreciseScrollingDeltas ? 1 : 8
            ScrollEngine.shared.nudge(-Double(event.scrollingDeltaY) * scale)
            return nil
        }

        if Preferences.shared.overlayVisible { show() }
    }

    func show() {
        guard let panel = panel else { return }
        panel.orderFrontRegardless()
        isVisible = true
        Preferences.shared.overlayVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        ScrollEngine.shared.isHovering = false
        Preferences.shared.overlayVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: Panel

    private func buildPanel() {
        let panel = PrompterPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar                       // above the menu bar and normal windows
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 260, height: 90)

        let container = TrackingContainer(frame: NSRect(x: 0, y: 0, width: 460, height: 150))
        container.onHover = { hovering in
            ScrollEngine.shared.isHovering = hovering
        }

        let host = NSHostingView(rootView: PrompterView())
        host.sizingOptions = []                        // the panel, not SwiftUI, decides the size
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        panel.contentView = container
        self.panel = panel
    }

    /// Keeps the prompter out of screen shares and screenshots.
    private func applyPrivacy() {
        panel?.sharingType = Preferences.shared.hideFromCapture ? .none : .readOnly
    }

    // MARK: Layout

    private func targetScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func applyLayout(force: Bool) {
        guard let panel = panel else { return }
        let prefs = Preferences.shared
        let screen = targetScreen()
        let notch = screen.notchInfo
        let inset: CGFloat = prefs.mode == .notch ? (notch?.height ?? 0) : 0

        if OverlayLayout.shared.topInset != inset {
            OverlayLayout.shared.topInset = inset
        }

        let key = "\(prefs.mode.rawValue)|\(prefs.notchWidth)|\(prefs.notchHeight)|\(screen.frame)|\(inset)"
        guard force || key != appliedLayoutKey else { return }
        appliedLayoutKey = key

        switch prefs.mode {
        case .notch:
            panel.styleMask.remove(.resizable)
            panel.isMovableByWindowBackground = false
            let width = max(prefs.notchWidth, (notch?.width ?? 0) + 40)
            let height = inset + prefs.notchHeight
            let frame = NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
            panel.setFrame(frame, display: true)

        case .floating:
            panel.styleMask.insert(.resizable)
            panel.isMovableByWindowBackground = true
            panel.setFrame(savedFloatingFrame(on: screen), display: true)
        }
    }

    private func savedFloatingFrame(on screen: NSScreen) -> NSRect {
        if let s = UserDefaults.standard.string(forKey: "floatingFrame") {
            let r = NSRectFromString(s)
            if r.width >= 200, r.height >= 80, screen.frame.intersects(r) { return r }
        }
        let visible = screen.visibleFrame
        return NSRect(x: visible.midX - 320, y: visible.maxY - 260, width: 640, height: 220)
    }

    private func saveFloatingFrame() {
        guard let panel = panel, Preferences.shared.mode == .floating else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "floatingFrame")
    }
}
