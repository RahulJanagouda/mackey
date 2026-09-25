import AppKit
import ApplicationServices

/// Dismisses every Notification Center alert macOS exposes to Accessibility.
/// There is no public API for this. Each alert carries a Close or Clear All action.
enum NotificationCleaner {
    struct Target {
        let element: AXUIElement
        let action: String
        let description: String
    }

    private static let dismissDescriptions: Set<String> = [
        "Close", "Clear All", "Clear",
        "Schließen", "Alle entfernen",
        "Cerrar", "Borrar todo",
        "关闭", "清除全部",
        "Fermer", "Tout effacer",
        "Закрыть", "Очистить все",
        "Fechar", "Limpar tudo",
        "閉じる", "すべてクリア",
        "Zamknij", "Wyczyść wszystko",
        "닫기", "모두 지우기",
    ]

    /// Lower runs first, so a stack is removed in one shot before individual closes.
    private static func rank(_ description: String) -> Int {
        switch description {
        case "Clear All", "Alle entfernen", "Borrar todo", "清除全部",
             "Tout effacer", "Очистить все", "Limpar tudo", "すべてクリア",
             "Wyczyść wszystko", "모두 지우기":
            return 0
        case "Clear":
            return 1
        default:
            return 2
        }
    }

    enum Result {
        case needsPermission
        case cleared(Int)
    }

    static func isTrusted(prompt: Bool) -> Bool {
        // AXIsProcessTrusted stays false for some local builds even after the
        // Accessibility switch is on. A real Accessibility call is the check
        // that matches what clearing notifications needs.
        if AXIsProcessTrusted() || accessibilityActuallyWorks() {
            return true
        }
        guard prompt else { return false }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        return AXIsProcessTrusted() || accessibilityActuallyWorks()
    }

    private static func accessibilityActuallyWorks() -> Bool {
        var focused: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        switch focusedResult {
        case .success, .noValue:
            return true
        case .apiDisabled:
            return false
        default:
            break
        }

        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        })?.processIdentifier else {
            return false
        }
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid),
            kAXWindowsAttribute as CFString,
            &windows
        )
        return result == .success || result == .noValue
    }

    static func count() -> Int {
        dismissables().count
    }

    static func clearAll() -> Result {
        guard isTrusted(prompt: true) else { return .needsPermission }
        let before = count()
        var previous = Int.max
        var stuckPasses = 0

        while true {
            let items = dismissables().sorted { rank($0.description) < rank($1.description) }
            if items.isEmpty { break }
            if items.count >= previous {
                stuckPasses += 1
                if stuckPasses >= 2 { break }
            } else {
                stuckPasses = 0
            }
            previous = items.count

            var performed = false
            for item in items {
                let error = AXUIElementPerformAction(item.element, item.action as CFString)
                if error == .success { performed = true }
            }
            if !performed { break }
        }

        return .cleared(max(0, before - count()))
    }

    private static func notificationCenter() -> AXUIElement? {
        let identifier = "com.apple.notificationcenterui"
        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == identifier
        })?.processIdentifier else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        return app
    }

    private static func dismissables() -> [Target] {
        guard let app = notificationCenter() else { return [] }
        let windows = copyAttribute(app, kAXWindowsAttribute) as [AXUIElement]? ?? []
        var found: [Target] = []
        for window in windows {
            collect(window, into: &found, depth: 0)
        }
        return found
    }

    private static func collect(_ element: AXUIElement, into found: inout [Target], depth: Int) {
        if depth > 12 { return }
        if let target = dismissTarget(element) {
            found.append(target)
            return
        }
        let children = copyAttribute(element, kAXChildrenAttribute) as [AXUIElement]? ?? []
        for child in children {
            collect(child, into: &found, depth: depth + 1)
        }
    }

    private static func dismissTarget(_ element: AXUIElement) -> Target? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let names = names as? [String] else {
            return nil
        }
        var match: (String, String)?
        for name in names {
            var description: CFString?
            AXUIElementCopyActionDescription(element, name as CFString, &description)
            let text = (description as String?) ?? ""
            guard dismissDescriptions.contains(text) else { continue }
            if match == nil || rank(text) < rank(match!.1) {
                match = (name, text)
            }
        }
        guard let match else { return nil }
        return Target(element: element, action: match.0, description: match.1)
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
