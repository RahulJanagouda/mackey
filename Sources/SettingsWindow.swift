import AppKit

final class ShortcutRecorderField: NSTextField {
    var shortcut: KeyboardShortcut {
        didSet { stringValue = shortcut.displayName }
    }
    var onChange: ((KeyboardShortcut) -> Bool)?

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        stringValue = shortcut.displayName
        isEditable = false
        isSelectable = false
        isBezeled = true
        bezelStyle = .roundedBezel
        alignment = .center
        font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        toolTip = "Click, then press a shortcut containing Control or Command"
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let candidate = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }
        if onChange?(candidate) == true {
            shortcut = candidate
        } else {
            NSSound.beep()
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let hotKeyManager: HotKeyManager
    private let controllerModeManager: ControllerModeManager
    private var fields: [HotKeyAction: ShortcutRecorderField] = [:]
    private let errorLabel = NSTextField(labelWithString: "")
    private lazy var controllerModeCheckbox = NSButton(
        checkboxWithTitle: "Enable Controller Mode on this Mac",
        target: self,
        action: #selector(toggleControllerMode)
    )
    private lazy var reverseDirectionCheckbox = NSButton(
        checkboxWithTitle: "Reverse horizontal gesture direction",
        target: self,
        action: #selector(toggleReverseDirection)
    )

    init(hotKeyManager: HotKeyManager, controllerModeManager: ControllerModeManager) {
        self.hotKeyManager = hotKeyManager
        self.controllerModeManager = controllerModeManager
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mackey Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        refreshFields()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Keyboard Shortcuts")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let explanation = NSTextField(wrappingLabelWithString:
            "Use combinations that your controlling Mac does not reserve. While Screen Sharing is focused, Mackey receives these shortcuts on the remote Mac."
        )
        explanation.textColor = .secondaryLabelColor

        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 18
        for action in HotKeyAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            label.alignment = .right
            let field = ShortcutRecorderField(
                shortcut: hotKeyManager.shortcuts[action] ?? action.defaultShortcut
            )
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 190).isActive = true
            field.onChange = { [weak self] shortcut in
                guard let self else { return false }
                let accepted = self.hotKeyManager.update(action: action, shortcut: shortcut)
                self.errorLabel.stringValue = accepted
                    ? ""
                    : "That shortcut is already in use. Choose another combination."
                return accepted
            }
            fields[action] = field
            grid.addRow(with: [label, field])
        }
        grid.column(at: 0).xPlacement = .trailing

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)

        let resetButton = NSButton(title: "Restore Defaults", target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded

        let note = NSTextField(wrappingLabelWithString:
            "Space switching uses macOS’s Control–Left/Right shortcuts. Keep “Move left a space” and “Move right a space” enabled in System Settings → Keyboard → Keyboard Shortcuts → Mission Control."
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let controllerTitle = NSTextField(labelWithString: "Screen Sharing Controller")
        controllerTitle.font = .systemFont(ofSize: 16, weight: .semibold)

        let controllerExplanation = NSTextField(wrappingLabelWithString:
            "Enable this only on the Mac controlling another Mac. While Apple Screen Sharing is foreground, hold Command and scroll horizontally with two fingers to switch Spaces on the remote Mac. Both Macs must use matching Previous/Next shortcuts."
        )
        controllerExplanation.textColor = .secondaryLabelColor
        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [
            title, explanation, grid, errorLabel, resetButton, note,
            separator, controllerTitle, controllerExplanation,
            controllerModeCheckbox, reverseDirectionCheckbox,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: explanation)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            controllerExplanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func refreshFields() {
        for action in HotKeyAction.allCases {
            fields[action]?.shortcut = hotKeyManager.shortcuts[action] ?? action.defaultShortcut
        }
        errorLabel.stringValue = ""
        controllerModeCheckbox.state = controllerModeManager.isEnabled ? .on : .off
        reverseDirectionCheckbox.state = controllerModeManager.reversesDirection ? .on : .off
        reverseDirectionCheckbox.isEnabled = controllerModeManager.isEnabled
    }

    @objc private func resetDefaults() {
        if hotKeyManager.resetToDefaults() {
            refreshFields()
        } else {
            errorLabel.stringValue = "A default shortcut is already in use."
        }
    }

    @objc private func toggleControllerMode() {
        controllerModeManager.setEnabled(controllerModeCheckbox.state == .on)
        reverseDirectionCheckbox.isEnabled = controllerModeManager.isEnabled
    }

    @objc private func toggleReverseDirection() {
        controllerModeManager.setReversesDirection(reverseDirectionCheckbox.state == .on)
    }
}
