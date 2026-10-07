import ApplicationServices
import Carbon.HIToolbox

enum SpaceDirection {
    case previous
    case next
}

enum SpaceSwitcher {
    static func move(_ direction: SpaceDirection) -> Bool {
        guard NotificationCleaner.isTrusted(prompt: true) else { return false }

        let keyCode = CGKeyCode(direction == .previous ? kVK_LeftArrow : kVK_RightArrow)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let controlDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_Control),
                  keyDown: true
              ),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let controlUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_Control),
                  keyDown: false
              ) else {
            return false
        }
        controlDown.flags = .maskControl
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        keyDown.flags = arrowFlags
        keyUp.flags = arrowFlags
        controlUp.flags = []
        // A menu action fires while AppKit is still dismissing the status menu.
        // Delay the complete chord so Mission Control receives it after menu tracking ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            controlDown.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            keyDown.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            keyUp.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) {
            controlUp.post(tap: .cghidEventTap)
        }
        return true
    }
}
