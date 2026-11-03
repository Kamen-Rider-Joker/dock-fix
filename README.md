<p align="center">
  <img src="Assets/AppIcon-1024.png" width="128" alt="DockUnstick icon">
</p>

<h1 align="center">DockUnstick</h1>

<p align="center">
  A tiny background app that un-sticks the macOS Dock when it stays shown after switching full-screen Spaces.
</p>

<p align="center">
  <b>English</b> | <a href="README.zh-CN.md">简体中文</a>
</p>

---

## Why this exists

Since macOS 27.2, the Dock has a bug that reproduces every time:

1. In a full-screen app, rest the cursor on an icon in the Dock;
2. Switch to another full-screen app by swiping on the trackpad or clicking a Dock icon;
3. While the switch animation is running, move the cursor quickly to the middle of the screen.

The Dock then **stays shown instead of hiding**, and the icon's name tooltip stays up, as if the cursor were still resting on it. Only moving the cursor back onto the Dock and out again, or running `killall Dock`, brings it back, and the next switch breaks it again. Plenty of people have reported the same thing, and the only workaround so far has been turning off magnification.

Until Apple fixes it, DockUnstick handles it in the background so you don't have to.

## The cause

Listening to the events the window server delivers to the Dock process shows that the problem is a **dropped "mouse exited" event**.

### Two players

- **The window server:** the part of the system that keeps track of the cursor. When the cursor enters the Dock, it tells the Dock "it came in" (event 8); when it leaves, it says "it left" (event 9).
- **The Dock:** on "it came in" it shows the hover effect and stays shown; on "it left" it drops the hover and hides. It never checks where the cursor is by itself; it relies entirely on these two messages.

### The key: "it left" is sent early, as soon as a switch starts

Whether or not the cursor has really left, the window server sends the Dock an "it left" as soon as a Space switch starts, even while the cursor is still resting on an icon. The Dock is busy running the switch animation at that moment and ignores it.

So on every switch the Dock misses one "it left". Whether it recovers depends on where the cursor is when the switch finishes.

The two examples below come from captured events. The switch was triggered by clicking a Dock icon; swiping on the trackpad goes exactly the same way, just without the click.

**Normal: the cursor is still on the Dock when the switch finishes**

| Time | What happens | Dock state |
|---|---|---|
| 31.06–31.19 | Click the WebStorm icon, the switch starts | Hovering |
| 31.23 | "It left" is sent early; the Dock ignores it | Still hovering |
| 31.49 | Switch finishes with the cursor still on the Dock; the window server sends "it came in" again | Hovering, matching reality |
| 31.57 | The cursor moves away; the window server sends "it left" and the Dock handles it | Hover ends, Dock hides ✅ |

**Stuck: the cursor leaves before the switch finishes**

| Time | What happens | Dock state |
|---|---|---|
| 36.54–36.66 | Click the WebStorm icon, the switch starts | Hovering |
| 36.70 | "It left" is sent early; the Dock ignores it | Still hovering |
| During the switch | The cursor moves quickly to the middle of the screen | Still hovering |
| 36.97 | Switch finishes with the cursor already outside the Dock | Still hovering ❌ |

Now the window server considers "it left" already delivered, and the cursor really is outside, so it sends nothing more. The Dock never got its "it left", believes the cursor is still on the icon, and never checks. So it stays stuck.

### An analogy

A doorman (the window server) sees a customer stand up and phones the shopkeeper (the Dock): "the customer left". But the shopkeeper is busy moving stock and misses the call.

- **The customer stays and comes back to the counter:** the doorman calls again with "a customer came in", the shopkeeper hears it, and later, when the customer really leaves, that call gets through too.
- **The customer slips out while the shopkeeper is busy:** the doorman thinks he has already called and doesn't call again, while the shopkeeper keeps thinking the customer is still in the shop.

What DockUnstick does is notice when the shopkeeper is still waiting on a customer, and **make that call again**.

## What it does

- **Records:** a listen-only event tap (`CGEvent.tapCreateForPid`) on the Dock process subscribes to just the "entered/exited" events and keeps the most recent "mouse exited" event.
- **Detects:** after every Space switch it checks once at 0.6, 1.2 and 2.0 seconds. If the cursor is no longer on the Dock but the Dock still has a hovered icon, or stays shown when it should have auto-hidden, the Dock is stuck.
- **Fixes:** it copies the saved "mouse exited" event, updates its time and cursor position, and delivers it to the Dock process (`CGEvent.postToPid`). Once the Dock gets the event it missed, it drops the hover and hides as usual.

Throughout, it **never moves the cursor, restarts the Dock, reads the screen or goes online**. It doesn't poll; it only checks a few times after each Space switch. Only public APIs are used.

Tested on the author's Mac: 8 of 8 stuck cases fixed, with the Dock hiding about 1 second after the Space switch.

## Installing

Requires macOS 13 or later. Runs on both Apple silicon and Intel Macs.

### Option 1: download a build

1. Download the latest `DockUnstick-x.y.z.zip` from [Releases](https://github.com/LLP2333/dockUnstick/releases), unzip it and drag `DockUnstick.app` into Applications;
2. The first time you open it, macOS says it can't verify the developer and refuses to open it. That's because this project isn't signed and notarized with a paid Apple Developer certificate. Go to **System Settings → Privacy & Security** and click "Open Anyway" near the bottom.

Alternatively, remove the download flag in Terminal, after which it opens normally:

```bash
xattr -dr com.apple.quarantine /Applications/DockUnstick.app
```

### Option 2: build from source

Requires Xcode or the Xcode Command Line Tools (for `swiftc`).

```bash
git clone https://github.com/LLP2333/dockUnstick.git
cd dockUnstick
./build.sh
```

Move the resulting `DockUnstick.app` into Applications before opening it:

```bash
mv DockUnstick.app /Applications/
open /Applications/DockUnstick.app
```

### Granting Accessibility

On first launch DockUnstick opens a setup window: click "Open System Settings" and turn on DockUnstick under **Privacy & Security → Accessibility**. The window notices the permission by itself, and you can close it afterwards.

> The app is ad-hoc signed, so **macOS treats every new build as a new app** and the old permission stops working. The switch then looks on but has no effect. Remove DockUnstick with **−** and add it again with **+**.

## Using it

DockUnstick runs in the background and doesn't appear in the Dock. Opening the app, or double-clicking it again while it runs, shows its window:

- **Status:** whether it's running, with a button to the setup window when Accessibility is missing;
- **Statistics:** total fixes, fixes today, the last fix and failures, plus a reset button;
- **Settings:**
  - "Show icon in menu bar": **off by default**. When on, the menu bar icon offers the same status, statistics and settings, and can open the window;
  - "Launch at login": uses the system login items; the first time you may need to allow it in System Settings → General → Login Items. When started at login, DockUnstick stays quiet and shows no window;
  - "Language": Same as System, 中文 or English. By default it follows the system: Chinese when your first preferred language is Chinese, English for any other language;
- open the log, open the project page, or quit.

## Settings

These can be changed with `defaults`. Apart from `language`, restart DockUnstick for a change to take effect:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `language` | string | `system` | UI language: `system` (follow the system), `zh` or `en`. Also switchable in the window, effective immediately |
| `trace` | bool | `true` | Log the Dock's state at every check |
| `checkDelays` | array | `0.6 1.2 2.0` | Seconds after a Space switch at which the Dock is checked |

```bash
defaults write local.dockunstick trace -bool false
defaults write local.dockunstick checkDelays -array 0.4 1.0 2.0
```

The log is at `~/Library/Logs/DockUnstick.log`. Past 1 MB it is renamed to `DockUnstick.log.1` (replacing the previous one) and a fresh log starts, so the two files together stay around 2 MB at most.

## Diagnostic modes

If a system update breaks the fix, these two modes help find out why:

```bash
# Log every event the window server delivers to the Dock for 60 seconds (mouse moves are only counted)
open DockUnstick.app --args --tap 60

# After 8 seconds, dump the Dock's accessibility info (icon positions, hover state and so on)
open DockUnstick.app --args --dump 8
```

Both write to the log file above. Quit the running DockUnstick first.

## Limitations

- This works around the bug rather than fixing it. A real fix needs Apple to re-check the cursor position once the Dock's switch animation ends. If you see this bug too, please report it to Apple with Feedback Assistant.
- The fix relies on the Dock's event format (type 9, "mouse exited"). If a future macOS changes it, the fix may stop working, and the log will show `fix: replayexit did not help`.
- When checking whether the Dock has hidden, only a Dock at the bottom of the main display is handled for now.

## Uninstalling

1. Open DockUnstick, turn off "Launch at login" and click "Quit DockUnstick";
2. Delete `DockUnstick.app`;
3. Remove DockUnstick under System Settings → Privacy & Security → Accessibility;
4. Optionally, clear its settings, statistics and logs:

```bash
defaults delete local.dockunstick
rm -f ~/Library/Logs/DockUnstick.log ~/Library/Logs/DockUnstick.log.1
```

## License

[MIT](LICENSE)
