import AppKit
import ServiceManagement

/// Mackey is a menu-bar toolbox. Each tool is a menu item added above the
/// first separator in `applicationDidFinishLaunching`.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let appName = "Mackey"
    private var statusItem: NSStatusItem!
    private let previousSpaceItem = NSMenuItem(title: "Previous Space", action: #selector(previousSpace), keyEquivalent: "")
    private let nextSpaceItem = NSMenuItem(title: "Next Space", action: #selector(nextSpace), keyEquivalent: "")
    private let clearItem = NSMenuItem(title: "Clear Notifications", action: #selector(clearNotifications), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private lazy var hotKeyManager = HotKeyManager { [weak self] action in
        self?.handleHotKey(action)
    }
    private lazy var settingsWindow = SettingsWindowController(hotKeyManager: hotKeyManager)
    private let notificationQueue = DispatchQueue(
        label: "com.rahuljanagouda.mackey.notifications",
        qos: .userInitiated
    )
    private var isClearing = false
    private var isCounting = false
    private var statusMessage: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        showIdleTitle()
        statusItem.button?.toolTip = appName

        previousSpaceItem.target = self
        nextSpaceItem.target = self
        clearItem.target = self
        loginItem.target = self
        statusLine.isEnabled = false
        statusLine.isHidden = true

        let menu = NSMenu()
        menu.delegate = self
        // Tools. Add the next one above the separator.
        menu.addItem(previousSpaceItem)
        menu.addItem(nextSpaceItem)
        menu.addItem(.separator())
        menu.addItem(clearItem)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        _ = hotKeyManager

        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLoginItem()
        if let statusMessage {
            statusLine.isHidden = false
            statusLine.title = statusMessage
        }
        guard !isClearing else { return }
        if NotificationCleaner.isTrusted(prompt: false) {
            refreshNotificationCount()
        } else {
            clearItem.title = "Clear Notifications"
        }
    }

    @objc private func clearNotifications() {
        guard !isClearing else { return }
        // The prompt has to run on the main thread, and it returns before the user answers.
        guard NotificationCleaner.isTrusted(prompt: true) else {
            showStatus("Turn \(appName) off and on in Accessibility, then try again")
            showIdleTitle()
            return
        }

        isClearing = true
        setTitle("Clearing…")
        showStatus("Clearing…")

        notificationQueue.async { [weak self] in
            let result = NotificationCleaner.clearAll()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isClearing = false
                switch result {
                case .needsPermission:
                    self.showStatus("Turn \(self.appName) off and on in Accessibility, then try again")
                    self.showIdleTitle()
                case .cleared(let count):
                    self.showStatus(count == 0 ? "Nothing to clear" : "Cleared \(count)")
                    self.flashTitle("Cleared")
                }
            }
        }
    }

    @objc private func previousSpace() {
        switchSpace(.previous)
    }

    @objc private func nextSpace() {
        switchSpace(.next)
    }

    @objc private func showSettings() {
        settingsWindow.present()
    }

    private func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .previousSpace:
            previousSpace()
        case .nextSpace:
            nextSpace()
        case .clearNotifications:
            clearNotifications()
        }
    }

    private func switchSpace(_ direction: SpaceDirection) {
        if SpaceSwitcher.move(direction) {
            flashTitle(direction == .previous ? "Space ←" : "Space →")
        } else {
            showStatus("Allow \(appName) in Accessibility, then try again")
        }
    }

    private func refreshNotificationCount() {
        guard !isCounting else { return }
        isCounting = true
        notificationQueue.async { [weak self] in
            let waiting = NotificationCleaner.count()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCounting = false
                guard !self.isClearing else { return }
                self.clearItem.title = waiting == 0
                    ? "Clear Notifications"
                    : "Clear Notifications (\(waiting))"
            }
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            statusLine.isHidden = false
            statusLine.title = "Couldn’t change login item"
        }
        updateLoginItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateLoginItem() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on
            loginItem.title = "Open at Login"
        case .requiresApproval:
            loginItem.state = .off
            loginItem.title = "Open at Login (approval needed)"
        default:
            loginItem.state = .off
            loginItem.title = "Open at Login"
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        statusLine.isHidden = false
        statusLine.title = message
    }

    private func showIdleTitle() {
        setTitle(appName)
    }

    private func flashTitle(_ title: String) {
        setTitle(title)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            self?.showIdleTitle()
        }
    }

    private func setTitle(_ title: String) {
        statusItem.button?.title = title
    }
}

if CommandLine.arguments.contains("--trusted") {
    fputs("\(NotificationCleaner.isTrusted(prompt: false))\n", stdout)
    exit(0)
}

if CommandLine.arguments.contains("--test-spaces") {
    final class SpaceChangeProbe {
        var count = 0
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let probe = SpaceChangeProbe()
    let notifications = NSWorkspace.shared.notificationCenter
    let observer = notifications.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        probe.count += 1
    }

    func waitForSpaceChange(after previousCount: Int) -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        while probe.count == previousCount, Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
        return probe.count > previousCount
    }

    let beforeNext = probe.count
    let sentNext = SpaceSwitcher.move(.next)
    let movedNext = sentNext && waitForSpaceChange(after: beforeNext)
    var movedPrevious = false
    var returnedToOriginal = false
    if movedNext {
        let beforeReturn = probe.count
        _ = SpaceSwitcher.move(.previous)
        returnedToOriginal = waitForSpaceChange(after: beforeReturn)
    } else {
        let beforePrevious = probe.count
        let sentPrevious = SpaceSwitcher.move(.previous)
        movedPrevious = sentPrevious && waitForSpaceChange(after: beforePrevious)
        if movedPrevious {
            let beforeReturn = probe.count
            _ = SpaceSwitcher.move(.next)
            returnedToOriginal = waitForSpaceChange(after: beforeReturn)
        }
    }

    notifications.removeObserver(observer)
    let passed = (movedNext || movedPrevious) && returnedToOriginal
    fputs(
        passed ? "PASS: Space changed and returned\n" : "FAIL: Space round trip was not completed\n",
        stdout
    )
    exit(passed ? 0 : 1)
}

if CommandLine.arguments.contains("--previous-space") || CommandLine.arguments.contains("--next-space") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let direction: SpaceDirection = CommandLine.arguments.contains("--previous-space") ? .previous : .next
    fputs("\(SpaceSwitcher.move(direction))\n", stdout)
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    exit(0)
}

if CommandLine.arguments.contains("--count") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    fputs("\(NotificationCleaner.count())\n", stdout)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
