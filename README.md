# Clear Notifications

A macOS menu-bar app that dismisses every notification in Notification Center.

Click the bell in the menu bar and choose **Clear All Notifications**. The app stays out of the Dock. **Open at Login** keeps it running after a restart.

macOS has no public API for clearing another app’s notifications. This app uses Accessibility to press each alert’s Close or Clear All action, including grouped stacks.

## Requirements

- macOS 14 or later
- Swift command-line tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/RahulJanagouda/clear-notifications.git
cd clear-notifications
./build.sh
```

`build.sh` compiles the app and installs it to `~/Applications/Clear Notifications.app`, then launches nothing on its own. Open the app once:

```bash
open "$HOME/Applications/Clear Notifications.app"
```

## Accessibility access

The first time you clear notifications, macOS asks you to allow Clear Notifications under **System Settings → Privacy & Security → Accessibility**.

Turn the switch on, then choose **Clear All Notifications** again. If the switch is already on and macOS still prompts, turn it off and back on. Rebuilding the app changes its signature, so a new build needs that switch flipped again.

## Menu

| Item | What it does |
| --- | --- |
| Clear All Notifications | Dismisses the notifications currently in Notification Center. The label includes the count when Accessibility access is granted. |
| Open at Login | Registers the app as a login item. |
| Quit Clear Notifications | Quits the menu-bar app. |

The icon briefly turns into a checkmark after a clear.

## Develop

The app is one Swift file, `Sources/main.swift`, plus `Info.plist` and `icon.swift`. `LSUIElement` is set so it runs as a menu-bar agent.

```bash
./build.sh
```

Override the install location with `CLEAR_APP_DEST` if you want the bundle somewhere other than `~/Applications`.
