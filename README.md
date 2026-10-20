# Notch Shelf

A Dynamic Island–style shelf for the MacBook notch. Pin screenshots, text and files
at the top of the screen so you can copy or drag them into any app without
switching windows.

## Features

- **Small island by default.** A compact pill around the notch shows your latest items and a count.
- **Hover to expand.** Move the cursor onto the pill and it springs open with a wobble. Move away and it shrinks back.
- **Drag in, drag out.** Drop screenshots, files or text onto the island. Drag cards out into Slack, Mail, an editor, anywhere.
- **Copy with one click.** Every card has a Copy button; double-click opens images and files.
- **Auto-catch screenshots.** New screenshots (⌘⇧3 / ⌘⇧4 / ⌘⇧5) land on the shelf automatically.
- **Clipboard history.** Everything you copy goes into the **Recent** tab (last 30). Pin the ones you want to keep.
- **Secret blur.** Text that looks like an API key, token, private key or card number is blurred until you click it.
  Copies from password managers are never recorded.
- **Looks.** Solid, Transparent or Glass background; None, Hairline, Accent, Glow, Double or Pulse outline in five colors.
  The island curves out into the top edge of the screen like the system notch.
- **Cleanup.** Unstarred items expire after 1 day / 3 days / 1 week (or never). Star an item to keep it.
- Works on Macs without a notch too (the island sits in the middle of the menu bar).

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥ Space | Keep the island open / let it close |
| ⌥ ⌘ V | Pin whatever is on the clipboard |
| Right-click a card | Copy, Open, Show in Finder, Pin, Star, Remove |

## Requirements

- macOS 13 Ventura or newer (Apple silicon or Intel)
- Xcode 15+ **or** just the Command Line Tools (`xcode-select --install`)

## Build and install

```bash
cd ~/Documents/workspace/NotchShelf
./scripts/build-app.sh
open "build/Notch Shelf.app"                 # try it
cp -R "build/Notch Shelf.app" /Applications/ # install it
```

To work on it in Xcode: `open Package.swift`, pick the **NotchShelf** scheme and press ⌘R.

### First launch

- The app has no Dock icon. Look for the tray icon in the menu bar (Settings, Quit) and the island at the notch.
- If macOS asks for access to your **Desktop** folder, allow it: that's where screenshots are saved by default.
- The app is signed locally ("ad-hoc"), so it runs on the Mac that built it. To share it with others you'd need
  an Apple Developer account to sign and notarize it.

## Project layout

```
Sources/NotchShelf/
  App/          entry point, app delegate, menu bar icon
  Models/       ShelfItem, AppSettings
  Services/     ShelfStore (items + files), clipboard & screenshot watchers, hot keys, secret detector
  Island/       panel over the notch, hover logic, island shape, SwiftUI views
  Settings/     settings window
Resources/Info.plist
scripts/build-app.sh
```

Data lives in `~/Library/Application Support/NotchShelf/` (`items.json` plus stored images).
Pinned files are referenced in place, not copied.
