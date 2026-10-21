# Perch

<img src="Resources/AppIcon-1024.png" width="128" alt="Perch app icon: a little bird on the island">

A Dynamic Island–style shelf for the MacBook notch. Pin screenshots, text and files
at the top of the screen so you can copy or drag them into any app without
switching windows.

## Features

- **Small island by default.** A compact pill around the notch shows your latest items and a count.
- **Hover to expand.** Move the cursor onto the pill and it springs open with a wobble. Move away and it shrinks back.
- **Drag in, drag out.** Drop screenshots, files or text onto the island. Drag cards out into Slack, Mail, an editor, anywhere.
- **Newest first, scroll for more.** Compact cards in a sideways-scrolling row. The edges fade and an arrow shows how many more cards are hidden. Trackpad swipes and the mouse wheel both scroll it.
- **Fix a card's position.** Hover a card and click the pin, or right-click and choose Fix at the Front. Fixed cards stay at the front and never expire.
- **Optional filter tabs.** By default the shelf shows everything. Turn on Settings → Shelf → Show filter tabs to get All, Images, Text, Files and Recent (a dropdown in the side panel).
- **Copy with one click.** Every card has a Copy button; double-click opens images and files.
- **Auto-catch screenshots.** New screenshots (⌘⇧3 / ⌘⇧4 / ⌘⇧5) land on the shelf automatically. Perch watches the folder screenshots are saved to (Screenshot app → Options → Save to), so allow access when macOS asks for that folder.
- **Clipboard history.** Everything you copy shows up on the shelf and in the **Recent** tab (last 30), and counts toward the badge. Copies expire like other items; star them to keep them.
- **Secret blur.** Text that looks like an API key, token, private key or card number is blurred until you click it.
  Copies from password managers are never recorded.
- **Claude Code sessions.** A small Claude mark on the island shows your running Claude Code sessions: it spins while one is working, pulses amber when one needs you, and is grey when they're idle. Open the island and click the Claude logo at the top right to switch the cards to your sessions, with full usage meters at the bottom (click it again to go back to the shelf). The ring around the logo fills with your 5-hour usage, so you can check it without switching. Clicking a desktop-app session opens it in the Claude app. Clicking a terminal session brings its terminal to the front and selects the exact tab in Terminal and iTerm2 (macOS asks once for permission). Right-click a terminal session to open a copy in the Claude app. Status comes from `~/.claude/sessions/`, an undocumented format that a Claude update could change. Turn off just this in Settings → Claude Code, or switch off Show Claude to hide everything Claude.
- **Claude plan usage.** The Claude view shows your 5-hour and weekly limits in Claude orange: percent used, with a live countdown to each reset underneath its bar. The numbers come from a Claude Code status line script, `scripts/claude-statusline.sh`, installed to `~/.claude/perch/statusline.sh` and set as `statusLine` in `~/.claude/settings.json`. It updates whenever a Claude Code session gets a reply. When those numbers are missing or older, the row falls back to the Claude app's own usage history, which it only samples now and then; numbers older than an hour show greyed out with "as of". Turn off just this in Settings → Claude Code, or switch off Show Claude to hide everything Claude.
- **Position and style.** In Settings → Placement, put the island on the top, left or right edge, and pick a style: Notch (joined to the edge), Floating (a capsule) or Orb (a circle with the item count). Both can be dragged anywhere on screen: drag the capsule or orb, or the open shelf by its header; it remembers where you put it, and Settings → Reset position moves it back. Left and right open a tall side panel with a 2-column card grid that scrolls down. Clicking the collapsed island opens it.
- **Looks.** Solid, Transparent or Glass background; None, Hairline, Accent, Glow, Double or Pulse outline in five colors.
  The island curves out into the top edge of the screen like the system notch.
- **Cleanup.** Unstarred items expire after 1 day / 3 days / 1 week (or never). Star an item to keep it.
- Works on Macs with and without a notch. With a notch (top position, Notch style) the island wraps around it; without one it becomes a small pill in the middle of the menu bar. If you close the lid or connect an external display, it moves to the right screen.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥ Space | Keep the island open / let it close |
| ⌥ ⌘ V | Pin whatever is on the clipboard |
| Right-click a card | Copy, Open, Show in Finder, Pin, Fix at the Front, Star, Remove |

## Requirements

- macOS 13 Ventura or newer (Apple silicon or Intel)
- Xcode 15+ **or** just the Command Line Tools (`xcode-select --install`)

## Build and install

```bash
cd ~/Documents/Workspace/perch
./scripts/build-app.sh
open build/Perch.app                 # try it
cp -R build/Perch.app /Applications/ # install it
```

To work on it in Xcode: `open Package.swift`, pick the **Perch** scheme and press ⌘R.

### First launch

- The app has no Dock icon. Look for the tray icon in the menu bar (Settings, Quit) and the island at the notch.
- If macOS asks for access to your **Desktop** or **Documents** folder, allow it: that's where screenshots are saved.
- The app is signed locally ("ad-hoc"), so it runs on the Mac that built it. To share it with others you'd need
  an Apple Developer account to sign and notarize it.

## Project layout

```
Sources/Perch/
  App/          entry point, app delegate, menu bar icon
  Models/       ShelfItem, AppSettings
  Services/     ShelfStore (items + files), clipboard & screenshot watchers, hot keys, secret detector
  Island/       panel over the notch, hover logic, island shape, SwiftUI views
  Settings/     settings window
Resources/Info.plist
scripts/build-app.sh
```

Data lives in `~/Library/Application Support/Perch/` (`items.json` plus stored images).
Pinned files are referenced in place, not copied.
