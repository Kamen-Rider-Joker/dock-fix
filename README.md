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
- **Detects:** right after every Space switch it checks once; if the cursor is still on the Dock, or a fix didn't take, it checks again at a set interval, by default up to 3 more times, 0.5 seconds apart. If the cursor is no longer on the Dock but the Dock still has a hovered icon, or stays shown when it should have auto-hidden, the Dock is stuck.
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

On first launch, click the DockUnstick icon in the menu bar and choose "Grant…" in the panel. Turn on DockUnstick under **Privacy & Security → Accessibility**. The panel notices the permission automatically and will not keep opening additional setup windows.

> The app is ad-hoc signed, so **macOS treats every new build as a new app** and the old permission stops working. The switch then looks on but has no effect. Remove DockUnstick with **−** and add it again with **+**.
>
> For development, a Developer ID certificate provides a stable identity: `CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build.sh`.

## Using it

DockUnstick runs in the background and doesn't appear in the Dock. Clicking its menu bar icon opens a lightweight anchored panel. Opening it again while it is already running shows the same panel without creating a regular window:

- **Status:** whether it's running, with a direct link to Accessibility settings when permission is missing;
- **Rescue dashboard:** today's rescues are the headline, with a rescue rank, streak, total fixes, success rate, last fix and seven-day activity chart;
- **Settings:**
  - "Launch at login": uses the system login items; the first time you may need to allow it in System Settings → General → Login Items. When started at login, DockUnstick stays quiet and does not open the panel;
  - "Language": Same as System, 中文 or English. By default it follows the system: Chinese when your first preferred language is Chinese, English for any other language;
  - "Menu bar icon": `dockUnstick (Default)` preserves the original icon. Choose from 23 alternatives, including clouds, arcade, avatars, animals and color Emoji. The change applies immediately;
  - "Write logs": **off by default**. Logs are written only when this is enabled; the `--dump` and `--tap` diagnostic modes still log temporarily;
  - "Repair pacing": adjust the retries and interval. The Dock is checked right after a Space switch; when that can't confirm it's fine (the cursor is still on it, or a fix didn't take), it is checked again at the interval. Retries 0–5, **3 by default**; interval 0.1–1 second, **0.5 by default**. A change applies from the next Space switch;
- open the log, open the project page, reset statistics or quit.

## Settings

These can be changed with `defaults`. Apart from `language`, `menuBarIcon`, `loggingEnabled`, `retryCount` and `retryInterval`, restart DockUnstick for a change to take effect:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `language` | string | `system` | UI language: `system` (follow the system), `zh` or `en`. Also switchable in the panel, effective immediately |
| `menuBarIcon` | string | `original` | Menu bar artwork. Values: `original`, `rocket`, `protection`, `diagnostics`, `cat`, `game`, `puzzle`, `lightning`, `cloud`, `cloudSun`, `arcade`, `bobAvatar`, `tuftAvatar`, `twinTailAvatar`, `bird`, `fish`, `alien`, `panda`, `fox`, `frog`, `bubbleTea`, `sushi`, `ghost` or `robot` |
| `loggingEnabled` | bool | `false` | Write diagnostic logs. Also switchable in the panel |
| `trace` | bool | `true` | When logging is enabled, record the Dock's state at every check |
| `retryCount` | integer | `3` | How many more checks at most when the first can't confirm the Dock is fine (0–5). Also adjustable in the panel |
| `retryInterval` | number | `0.5` | Seconds between those checks (0.1–1). Also adjustable in the panel |

```bash
defaults write local.dockunstick trace -bool false
defaults write local.dockunstick retryCount -int 5
defaults write local.dockunstick retryInterval -float 0.2
```

Logging is off by default. When enabled, the log is at `~/Library/Logs/DockUnstick.log`. Past 1 MB it is renamed to `DockUnstick.log.1` (replacing the previous one) and a fresh log starts, so the two files together stay around 2 MB at most.

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
