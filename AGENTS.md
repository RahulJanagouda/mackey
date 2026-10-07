# Mackey contributor context

## Product boundaries

- Mackey is a small AppKit menu-bar utility. Keep it Dockless (`LSUIElement`) and avoid adding a package manager or third-party runtime unless the feature genuinely requires one.
- The deployment target is macOS 14. The release artifact must remain Universal (`arm64` and `x86_64`).
- There is no public macOS API to clear another app’s notifications or switch directly between Spaces. These features intentionally use documented Accessibility calls and synthetic standard keyboard events. Do not introduce private Dock, Mission Control, or Spaces APIs.

## Threading and input

- All AppKit UI mutations must happen on the main thread.
- Notification Center Accessibility traversal can block. Keep counting and clearing on the dedicated serial `notificationQueue`; never move it back to the main thread.
- Register only explicit global shortcuts with `RegisterEventHotKey`. Do not add a general event tap or keyboard logger. Shortcut recording must require Control or Command.
- Space switching synthesizes `Control–Left/Right`. It depends on the corresponding Mission Control shortcuts remaining enabled in System Settings.
- Screen Sharing may intercept shortcuts on the controlling Mac. Defaults must remain uncommon, and shortcuts must stay user-configurable.

## Permissions and signing

- Accessibility permission is required for notification manipulation and synthetic Space-switch events.
- Local builds prefer the persistent `Mackey Development` identity in the login Keychain so Accessibility approval survives rebuilds. `MACKEY_CODESIGN_IDENTITY` overrides it. If no persistent identity exists, `build.sh` falls back to ad-hoc signing with a warning.
- Public GitHub builds must use an Apple Development or Developer ID identity when available. Do not distribute the local self-signed certificate or its private key. An intentionally ad-hoc public artifact must be built with `MACKEY_CODESIGN_IDENTITY=-` and documented as such.
- Never claim that a build is notarized or persistently signed unless the signing setup has actually changed and has been verified.

## Build and verification

- Build with `./build.sh`; set `MACKEY_APP_DEST` to a temporary path for verification so development checks do not overwrite the installed copy.
- After implementing a user-visible change, always run the verification build, install it with `./build.sh`, relaunch Mackey, and open the relevant UI so the user can inspect the result. Do not stop after type-checking or compiling.
- Before shipping, verify:
  - `swiftc -warnings-as-errors -typecheck` succeeds with AppKit, Carbon, and ServiceManagement.
  - `lipo -archs` reports both `arm64` and `x86_64`.
  - `codesign --verify --deep --strict` succeeds.
  - `Info.plist` has the intended marketing and build versions.
  - `Mackey --count` exits successfully.
- Release versions use `vMAJOR.MINOR` tags, `Mackey MAJOR.MINOR` titles, and `Mackey-MAJOR.MINOR.zip` assets. Increment `CFBundleVersion` for every release.
