import Foundation
import Carbon.HIToolbox

/// System-wide keyboard shortcuts. These use the Carbon hot-key API,
/// which does not need the Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        installIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C45_4354), id: id)   // 'LECT'
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref = ref {
            handlers[id] = handler
            refs.append(ref)
        } else {
            NSLog("Lectern: could not register hot key \(keyCode) (status \(status)); another app may own it.")
        }
    }

    fileprivate func fire(_ id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            self?.handlers[id]?()
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    HotKeyCenter.shared.fire(hotKeyID.id)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
