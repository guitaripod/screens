# screens

Turn external displays off on macOS without unplugging them, the way `xrandr --output X --off` or KDE's display settings do on Linux. A display that is off acts as if its cable were pulled: windows move to the screens that stay on, and the display sleeps. `screens on`, logging out or restarting brings it back, with the same arrangement, resolution, refresh rate and main display as before.

```
screens                  # external displays off, or back on when none is on
screens off              # every external display off
screens on               # back on
screens off ark          # only displays whose name contains "ark"
screens tv               # toggle only the displays matching "tv"
screens status           # state, resolution, refresh rate, main display
screens status --json
```

```
on   1  Built-in Retina Display  3600x2338  120 Hz  main, built-in
off  2  Odyssey Ark
on   4  LG TV SSCR2              3840x2160  60 Hz
off  5  LG ULTRAGEAR+
```

A name matches any part of a display's name, ignoring case, or its exact id from `screens status`. Every matching display is affected, so use the id when a name matches more than one or is a command word. Words after the command are joined, so `screens off lg tv` matches "LG TV".

`screens` never turns off the built-in display or the last display that is on.

Exit status: 0 when done or nothing to do (including "already off"), 1 when a display could not be changed or no display matches, 2 for a usage error.

## Install

```
scripts/install.sh
```

Builds a release binary into `~/.local/bin/screens`, which needs to be on your `PATH`. Requires macOS 13 or later and Swift 6. Tested on Apple Silicon with macOS 27.

## How it works

macOS has no public API for this. `screens` calls `SLSConfigureDisplayEnabled` from the private SkyLight framework inside a `CGBeginDisplayConfiguration` transaction that lasts for the login session, one display at a time, because several displays in one transaction take seconds each and settle out of order.

A display that is off disappears from every display list, so `screens` writes it to `~/Library/Application Support/screens/disabled.json` before turning it off, along with the login session. The list is ignored after logout or restart, when macOS has already brought the displays back. A display unplugged while off stays on the list until it comes back on or the session ends. A lock keeps overlapping runs from overwriting each other's list.

## Limits

A display that is unplugged and plugged back in while off stays off until you log out. macOS remembers it as turned off but gives it no display id, so nothing can address it: no display list includes it, its UUID resolves to nothing, and turning on every id fails. Once another display has taken its old id, `screens status` lists it as `stuck` and `screens on` says so instead of turning on the wrong display; before that, `screens on` fails with a message that names both causes, unplugged or stuck. Logging out brings it back, and so does every display disconnecting at once, such as unplugging a dock with the lid closed. BetterDisplay, Lunar and the other tools built on the same call share this limit.

Display ids change when displays reconnect, for example after sleep or when unplugging one display briefly drops another that shares its path. `screens` therefore matches displays by UUID once they are back.

A future macOS can remove the private call. `screens` then reports the error instead of doing anything.

## License

GPL-3.0
