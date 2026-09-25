# Mackey

A macOS menu-bar toolbox. Clear Notifications is the first tool. More can be added as menu items later.

Mackey stays out of the Dock. Click **Mackey** in the menu bar, then choose a tool.

## Requirements

- macOS 14 or later
- Swift command-line tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/RahulJanagouda/mackey.git
cd mackey
./build.sh
open "$HOME/Applications/Mackey.app"
```

`build.sh` installs the app to `~/Applications/Mackey.app`. Set `MACKEY_APP_DEST` to install somewhere else.

## Clear Notifications

macOS has no public API for clearing another app’s notifications. This tool uses Accessibility to press each alert’s Close or Clear All action, including grouped stacks.

The first time you use it, allow **Mackey** under **System Settings → Privacy & Security → Accessibility**, then choose **Clear Notifications** again. If the switch is already on and macOS still prompts, turn it off and back on. A new build has a new signature, so the switch needs to be flipped again after you rebuild.

## Menu

| Item | What it does |
| --- | --- |
| Clear Notifications | Dismisses the notifications currently in Notification Center. The label includes the count when Accessibility access is granted. |
| Open at Login | Registers Mackey as a login item. |
| Quit Mackey | Quits the menu-bar app. |

New tools go in `Sources/main.swift`, above the first separator in the menu.

## Develop

```bash
./build.sh
```

`Sources/main.swift` is the menu bar. `Sources/ClearNotifications.swift` is the clear-notifications tool. `LSUIElement` in `Info.plist` keeps Mackey out of the Dock.
