import AppKit
import ServiceManagement

/// Mackey is a menu-bar toolbox. Each tool is a menu item added above the
/// first separator in `applicationDidFinishLaunching`.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let appName = "Mackey"
    private var statusItem: NSStatusItem!
    private let clearItem = NSMenuItem(title: "Clear Notifications", action: #selector(clearNotifications), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var isClearing = false
    private var statusMessage: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        showIdleTitle()
        statusItem.button?.toolTip = appName

        clearItem.target = self
        loginItem.target = self
        statusLine.isEnabled = false
        statusLine.isHidden = true

        let menu = NSMenu()
        menu.delegate = self
        // Tools. Add the next one above the separator.
        menu.addItem(clearItem)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLoginItem()
        if let statusMessage {
            statusLine.isHidden = false
            statusLine.title = statusMessage
        }
        guard !isClearing else { return }
        if NotificationCleaner.isTrusted(prompt: false) {
            let waiting = NotificationCleaner.count()
            clearItem.title = waiting == 0
                ? "Clear Notifications"
                : "Clear Notifications (\(waiting))"
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let result = NotificationCleaner.clearAll()
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
