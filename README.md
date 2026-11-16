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

A display that is off disappears from every display list, so `screens` writes it to `~/Library/Application Support/screens/disabled.json` before turning it off, along with the login session. The list is ignored after logout or restart, when macOS has already brought the displays back. A display unplugged while off stays on the list until it is plugged in again and `screens on` succeeds. A lock keeps overlapping runs from overwriting each other's list.

A future macOS can remove the private call. `screens` then reports the error instead of doing anything.

## License

GPL-3.0
