# Mackey

Mackey is a lightweight macOS menu-bar toolbox for clearing Notification Center and controlling Spaces with ease of shortcuts, including while using Apple Screen Sharing.

You might say, I can open the "notification drawer", expand on "all notification", and then click on "clear" and then on "all notifications". but thats 4 steps every time you want to clear, this app does all that and more with shortcuts.

My use case: I use my home security camera which sends persistent notifications on to mac os. I cant turn them off nor all are interesting. I use this for that.

It stays out of the Dock. Click **Mackey** in the menu bar to use a tool or open Settings.

## Requirements

- macOS 14 or later
- Accessibility permission for clearing notifications and switching Spaces
- Swift command-line tools (`xcode-select --install`) when building from source

## Install from source

```bash
git clone https://github.com/RahulJanagouda/mackey.git
cd mackey
./build.sh
open "$HOME/Applications/Mackey.app"
```

`build.sh` creates a Universal Apple silicon/Intel app at `~/Applications/Mackey.app`. Set `MACKEY_APP_DEST` to install somewhere else.

The build script prefers a persistent `Mackey Development` identity in the login Keychain. With that identity installed, local rebuilds keep the same code identity and retain Accessibility approval. If the identity is unavailable, the script falls back to ad-hoc signing and warns that macOS may require Accessibility permission again after each rebuild.

Set `MACKEY_CODESIGN_IDENTITY` to choose another identity. Public builds should use an Apple Development or Developer ID certificate; use `MACKEY_CODESIGN_IDENTITY=-` only when an intentionally ad-hoc artifact is required.

## Keyboard shortcuts

Mackey registers three global shortcuts. Open **Mackey → Settings…** and click a shortcut field to record a different combination. Shortcuts must contain Control or Command.

| Action | Default shortcut |
| --- | --- |
| Previous Space | `Control–Option–Command–Left` |
| Next Space | `Control–Option–Command–Right` |
| Clear Notifications | `Control–Option–Command–N` |

Settings are stored in the current user’s defaults and take effect immediately. **Restore Defaults** returns all three shortcuts to the values above.

### Using Spaces through Screen Sharing

Run Mackey on the Mac being controlled. Apple Screen Sharing normally consumes `Control–Left/Right` on the controlling Mac, so Mackey listens for uncommon combinations that Screen Sharing can forward. When remote Mackey receives one, it generates macOS’s standard `Control–Left/Right` shortcut on that Mac.

Keep **Move left a space** and **Move right a space** enabled under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control** on the remote Mac. Screen-sharing products differ in which shortcuts they forward; if a default is intercepted locally, choose another unused Control- or Command-based combination in Mackey Settings.

macOS provides no public API for selecting an adjacent Space. Mackey therefore uses Accessibility-authorized keyboard events rather than private Dock or Spaces APIs.

### Command + trackpad gesture

Install Mackey on both Macs, then configure them as follows:

1. On the remote Mac, leave **Screen Sharing Controller Mode** off and keep Mackey running.
2. On the controlling MacBook, enable **Mackey → Screen Sharing Controller Mode** or enable it in Settings.
3. Keep the Previous/Next shortcuts identical on both Macs.
4. With Apple Screen Sharing in the foreground, hold Command and scroll horizontally with two fingers.

The MacBook instance observes only precise Command-modified scroll events while Apple Screen Sharing is foreground. It forwards the configured Previous/Next shortcut into the session, and remote Mackey converts that shortcut into the standard Mission Control Space action. Controller Mode unregisters the local Previous/Next hotkeys so the MacBook does not consume the forwarded shortcut. Clear Notifications remains available locally.

If the gesture direction feels reversed, enable **Reverse horizontal gesture direction** in Settings. Apple’s system three-finger Space gesture cannot be intercepted reliably with public APIs, which is why Controller Mode uses a Command-modified two-finger horizontal scroll.

## Clear Notifications

macOS has no public API for clearing another app’s notifications. Mackey uses Accessibility to press each alert’s Close or Clear All action, including grouped stacks. Counting and clearing run on a serial worker queue so an unresponsive Notification Center cannot block the menu-bar UI.

The first time you use this tool, allow **Mackey** under **System Settings → Privacy & Security → Accessibility**, then try again.

## Menu

| Item | What it does |
| --- | --- |
| Previous Space | Moves to the adjacent Space on the left. |
| Next Space | Moves to the adjacent Space on the right. |
| Clear Notifications | Dismisses notifications currently in Notification Center. |
| Settings… | Records and saves global shortcuts. |
| Screen Sharing Controller Mode | Converts Command + two-finger horizontal scrolling into remote Space shortcuts. |
| Open at Login | Registers Mackey as a login item. |
| Quit Mackey | Quits the menu-bar app. |

## Develop

```bash
./build.sh
```

The build script cross-compiles and combines `arm64` and `x86_64` executables, creates the app icon, and signs the resulting bundle with the selected identity.

Useful diagnostics for the installed build:

```bash
"$HOME/Applications/Mackey.app/Contents/MacOS/Mackey" --trusted
"$HOME/Applications/Mackey.app/Contents/MacOS/Mackey" --count
"$HOME/Applications/Mackey.app/Contents/MacOS/Mackey" --test-spaces
"$HOME/Applications/Mackey.app/Contents/MacOS/Mackey" --send-controller-next
```

`--test-spaces` performs a real round trip to an adjacent Space and reports success only after macOS emits Space-change notifications in both directions.

- `Sources/main.swift` owns the menu and application lifecycle.
- `Sources/HotKeys.swift` registers explicit Carbon hotkeys and persists their key codes.
- `Sources/ControllerMode.swift` observes Command-modified horizontal scrolling and forwards shortcuts to Screen Sharing.
- `Sources/SettingsWindow.swift` implements the native shortcut recorder UI.
- `Sources/SpaceSwitcher.swift` emits standard Mission Control keyboard events.
- `Sources/ClearNotifications.swift` traverses Notification Center’s Accessibility tree.
- `LSUIElement` in `Info.plist` keeps Mackey out of the Dock.
