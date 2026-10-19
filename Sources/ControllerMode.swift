import AppKit
import Carbon.HIToolbox

enum ControllerModeDefaults {
    static let enabled = "controllerMode.enabled"
    static let reverseDirection = "controllerMode.reverseDirection"
}

/// Watches horizontal trackpad scrolling on the Mac running Screen Sharing and
/// forwards Mackey's configured Space shortcut into the foreground session.
final class ControllerModeManager {
    private var monitor: Any?
    private var accumulatedX: CGFloat = 0
    private var didTriggerCurrentGesture = false
    private var lastTrigger = Date.distantPast
    private let shortcutProvider: (HotKeyAction) -> KeyboardShortcut?
    private let statusHandler: (String) -> Void
    private let enabledHandler: (Bool) -> Void

    private(set) var isEnabled: Bool
    var reversesDirection: Bool {
        didSet { UserDefaults.standard.set(reversesDirection, forKey: ControllerModeDefaults.reverseDirection) }
    }

    init(
        shortcutProvider: @escaping (HotKeyAction) -> KeyboardShortcut?,
        statusHandler: @escaping (String) -> Void,
        enabledHandler: @escaping (Bool) -> Void
    ) {
        self.shortcutProvider = shortcutProvider
        self.statusHandler = statusHandler
        self.enabledHandler = enabledHandler
        isEnabled = UserDefaults.standard.bool(forKey: ControllerModeDefaults.enabled)
        reversesDirection = UserDefaults.standard.bool(forKey: ControllerModeDefaults.reverseDirection)
        if isEnabled { startMonitoring() }
    }

    deinit { stopMonitoring() }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: ControllerModeDefaults.enabled)
        enabled ? startMonitoring() : stopMonitoring()
        enabledHandler(enabled)
    }

    func setReversesDirection(_ reversed: Bool) {
        reversesDirection = reversed
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard event.hasPreciseScrollingDeltas,
                  event.modifierFlags.contains(.command),
                  event.momentumPhase.isEmpty else { return }
            let deltaX = event.scrollingDeltaX
            let phase = event.phase
            let inverted = event.isDirectionInvertedFromDevice
            DispatchQueue.main.async {
                self?.handle(deltaX: deltaX, phase: phase, directionIsInverted: inverted)
            }
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        resetGesture()
    }

    private func handle(deltaX: CGFloat, phase: NSEvent.Phase, directionIsInverted: Bool) {
        guard isEnabled,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.ScreenSharing" else {
            resetGesture()
            return
        }

        if phase.contains(.began) { resetGesture() }
        guard !didTriggerCurrentGesture else {
            if phase.contains(.ended) || phase.contains(.cancelled) { resetGesture() }
            return
        }

        // Normalize to physical finger direction so Natural Scrolling does not
        // change which remote Space the gesture selects.
        let physicalDelta = directionIsInverted ? -deltaX : deltaX
        accumulatedX += reversesDirection ? -physicalDelta : physicalDelta
        guard abs(accumulatedX) >= 55, Date().timeIntervalSince(lastTrigger) > 0.45 else { return }

        didTriggerCurrentGesture = true
        lastTrigger = Date()
        let action: HotKeyAction = accumulatedX < 0 ? .nextSpace : .previousSpace
        guard let shortcut = shortcutProvider(action),
              let screenSharing = NSWorkspace.shared.frontmostApplication else { return }
        KeyboardShortcutSender.send(shortcut, to: screenSharing.processIdentifier)
        statusHandler(action == .nextSpace ? "Remote Space →" : "Remote Space ←")
    }

    private func resetGesture() {
        accumulatedX = 0
        didTriggerCurrentGesture = false
    }
}

enum KeyboardShortcutSender {
    static func send(_ shortcut: KeyboardShortcut, to processID: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let modifierKeys: [(UInt32, CGKeyCode, CGEventFlags)] = [
            (UInt32(controlKey), CGKeyCode(kVK_Control), .maskControl),
            (UInt32(optionKey), CGKeyCode(kVK_Option), .maskAlternate),
            (UInt32(shiftKey), CGKeyCode(kVK_Shift), .maskShift),
            (UInt32(cmdKey), CGKeyCode(kVK_Command), .maskCommand),
        ]
        let activeModifiers = modifierKeys.filter { shortcut.modifiers & $0.0 != 0 }
        var flags: CGEventFlags = []
        var events: [CGEvent] = []

        for (_, keyCode, flag) in activeModifiers {
            flags.insert(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
            event.flags = flags
            events.append(event)
        }

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(shortcut.keyCode),
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(shortcut.keyCode),
            keyDown: false
        ) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        events.append(keyDown)
        events.append(keyUp)

        for (_, keyCode, flag) in activeModifiers.reversed() {
            flags.remove(flag)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
            event.flags = flags
            events.append(event)
        }

        for (index, event) in events.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.018) {
                event.postToPid(processID)
            }
        }
    }
}
