# AGENTS.md

Instructions for AI coding agents working in this repository.

## Install Odak for the user (macOS)

When the user asks you to install, set up or run Odak on their Mac, run:

```bash
scripts/install.sh
```

It checks the requirements, builds the app from source, copies it to `/Applications` (or `~/Applications`
when `/Applications` is not writable), registers the "Read with Odak" service and opens the app.
It is safe to run again to update. Because the app is built on the user's Mac, macOS shows no
Gatekeeper warning, and no Apple Developer account is needed.

Requirements:
- macOS 14 (Sonoma) or later.
- Swift 6 or later (from Xcode or Apple's Command Line Tools). If neither is installed, the script opens
  Apple's installer and waits for it: tell the user to click **Install** in the system dialog (you cannot
  click it for them). Run the script in the background or with a long timeout; the download takes minutes.
  If it reports Swift older than 6, the user must update Xcode or the Command Line Tools in
  System Settings › General › Software Update.

After installing, tell the user:
- Select text in any app, right-click › Services › **Read with Odak**. If it is not listed:
  System Settings › Keyboard › Keyboard Shortcuts… › Services › Text › enable **Read with Odak**.
- In the app: paste text or open a file (TXT, Markdown, PDF, RTF, Word, HTML, ODT); the reader opens paused,
  click or press Space to start. Statistics: ⌘Y.

## Keyboard shortcut for "Read with Odak" (optional)

After installing, offer to add a shortcut that reads the selected text in Odak (default ⌃⌥⌘O). Ask the
user first and use the combination they choose. Steps:

1. Check for an existing setting and keep it if there is one (do not overwrite the user's choice):
   ```bash
   defaults read pbs NSServicesStatus 2>/dev/null | grep -A2 'com.halilbalci.odak'
   ```
2. Set the shortcut (this adds or replaces only Odak's entry; other services keep their settings):
   ```bash
   defaults write pbs NSServicesStatus -dict-add "com.halilbalci.odak - Read with Odak - readSelection" '{ key_equivalent = "@~^o"; }'
   /System/Library/CoreServices/pbs -update
   ```
   `key_equivalent` codes: `@` ⌘, `~` ⌥, `^` ⌃, `$` ⇧, then one lowercase letter. Prefer three modifiers
   (e.g. `@~^`): apps rarely use them, so the shortcut does not override an app's own shortcut.
3. Tell the user: select text in any app and press the shortcut. If it does nothing, log out and back in
   or check System Settings › Keyboard › Keyboard Shortcuts… › Services › Text › **Read with Odak**, where
   they can also change or remove it.

## Browser extension (any OS, optional)

The extension in `chrome-extension/` works on its own (Chrome, Edge, Brave; macOS, Windows, Linux).
Agents cannot load it; tell the user to open `chrome://extensions`, turn on **Developer mode**, click
**Load unpacked** and choose the absolute path of this repo's `chrome-extension` folder.

## Development

- Build and test: `swift build`, `swift test`, `node --test chrome-extension/tests/*.test.mjs`
  (on Node 25 pass the glob; the bare directory form fails).
- Run the app bundle: `scripts/build-app.sh`, then `open build/Odak.app`
  (Services, localization and file associations only work from the bundle, not `swift run`).
- UI strings are localized in `Resources/en.lproj` and `Resources/tr.lproj` `Localizable.strings`;
  add every new user-visible string to both. Extension strings live in `chrome-extension/_locales/{en,tr}`.
- Do not run `scripts/build-app.sh --release`: it signs and notarizes with the maintainer's
  Developer ID and keychain credentials.
