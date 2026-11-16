import CoreGraphics
import Foundation

let version = "0.1.0"
let store = DisabledStore()

let usage = """
usage: screens [toggle|off|on|status] [name]
       screens <name>          toggle just that display

  toggle  turn the external displays off, or back on when none is on (default)
  off     turn off every external display, or the ones whose name contains [name]
  on      turn back on the displays screens turned off, or the ones matching [name]
  status  list displays and whether they are on

Displays stay plugged in; turning one off is like pulling its cable until `screens on`,
a replug, or a restart.
"""

/// Writes a message to stderr and exits with the given status.
func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("screens: \(message)\n".utf8))
    exit(status)
}

/// Joins display names for a one-line report.
func names(_ displays: [Display]) -> String {
    displays.map(\.name).joined(separator: ", ")
}

func turnOff(_ query: String?) throws {
    let active = Displays.active()
    let targets = active.filter { !$0.builtIn && $0.matches(query) }
    guard !targets.isEmpty else {
        if query != nil { fail("no external display that is on matches \"\(query!)\"") }
        print("no external display is on")
        return
    }
    guard active.count > targets.count else {
        fail("turning off \(names(targets)) would leave no display on; open the lid or name one display")
    }
    var remembered = store.load().filter { entry in !targets.contains { $0.id == entry.id } }
    remembered.append(contentsOf: targets)
    try store.save(remembered)
    var off: [Display] = []
    var refused: [Display] = []
    for display in targets {
        if (try? Displays.setEnabled(false, id: display.id)) != nil, Displays.waitUntil({ !$0.contains(display.id) }) {
            off.append(display)
        } else {
            refused.append(display)
        }
    }
    if !off.isEmpty { print("off: \(names(off))") }
    if !refused.isEmpty { fail("still on: \(names(refused))") }
}

func turnOn(_ query: String?) throws {
    let remembered = store.load()
    let targets = remembered.filter { $0.matches(query) }
    guard !targets.isEmpty else {
        if query != nil { fail("no display screens turned off matches \"\(query!)\"") }
        print("no display was turned off by screens")
        return
    }
    var back: [Display] = []
    var missing: [Display] = []
    for display in targets {
        if (try? Displays.setEnabled(true, id: display.id)) != nil, Displays.waitUntil({ $0.contains(display.id) }) {
            back.append(display)
        } else {
            missing.append(display)
        }
    }
    try store.save(remembered.filter { entry in !back.contains { $0.id == entry.id } })
    if !back.isEmpty { print("on: \(names(back))") }
    if !missing.isEmpty {
        fail("did not come back (unplugged? replug it or run `screens on` again): \(names(missing))")
    }
}

func toggle(_ query: String?) throws {
    let anyOn = Displays.active().contains { !$0.builtIn && $0.matches(query) }
    if anyOn {
        try turnOff(query)
    } else {
        try turnOn(query)
    }
}

func status() {
    let active = Displays.active()
    let activeIDs = Set(active.map(\.id))
    let off = store.load().filter { !activeIDs.contains($0.id) }
    for display in active {
        let kind = display.builtIn ? "  (built-in)" : ""
        print("on   \(String(display.id).padding(toLength: 4, withPad: " ", startingAt: 0)) \(display.name)\(kind)")
    }
    for display in off {
        print("off  \(String(display.id).padding(toLength: 4, withPad: " ", startingAt: 0)) \(display.name)")
    }
}

let commands: Set = ["toggle", "off", "on", "status", "list", "--version", "-V", "version", "--help", "-h", "help"]
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first.map { commands.contains($0) } == true ? arguments.removeFirst() : "toggle"
let query = arguments.isEmpty ? nil : arguments.joined(separator: " ")

do {
    switch command {
    case "toggle": try toggle(query)
    case "off": try turnOff(query)
    case "on": try turnOn(query)
    case "status", "list": status()
    case "--version", "-V", "version": print("screens \(version)")
    case "--help", "-h", "help": print(usage)
    default: fail(usage, status: 2)
    }
} catch {
    fail("\(error)")
}
