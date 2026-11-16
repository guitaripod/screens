# screens

Turn external displays off on macOS without unplugging them, the way `xrandr --output X --off` or KDE's display settings do on Linux. A turned-off display leaves the desktop as if its cable were pulled: windows move to the remaining screens and the display sleeps. `screens on`, replugging the cable or restarting brings it back.

```
screens            # external displays off, or back on when none is on
screens off        # every external display off
screens on         # back on
screens off ark    # just the displays whose name contains "ark"
screens tv         # toggle just the matching display
screens status
```

It refuses to turn off the last display that is on, so with the lid closed you can only turn off some of the externals.

## Install

```
scripts/install.sh
```

Builds a release binary into `~/.local/bin/screens`. Needs macOS 13 or later and Swift 6. Tested on Apple Silicon with macOS 27.

## How it works

macOS has no public API for this. `screens` calls `SLSConfigureDisplayEnabled` from the private SkyLight framework inside a `CGBeginDisplayConfiguration` transaction, one display at a time, and remembers what it turned off in `~/Library/Application Support/screens/disabled.json` because a disabled display disappears from every display list. A future macOS can remove the call; `screens` then says so instead of doing anything.

## License

GPL-3.0
