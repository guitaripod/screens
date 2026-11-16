import CoreGraphics
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
}

struct Screens {
    private struct Outcome {
        var changed: [Display] = []
        var failed: [String] = []
    }

    private struct Row: Encodable {
        let id: CGDirectDisplayID
        let uuid: String?
        let name: String
        let state: String
        let builtIn: Bool
        let main: Bool
        let width: Int?
        let height: Int?
        let hertz: Int?
    }

    private let store = DisabledStore()

    func run(_ command: Command) throws {
        switch command {
        case .version:
            print("screens \(version)")
        case .help:
            print(Command.usage)
        case let .status(json):
            try status(json: json)
        case let .off(query):
            try store.lock()
            let (active, remembered) = try snapshot()
            try turnOff(query, active: active, remembered: remembered)
        case let .on(query):
            try store.lock()
            let (active, remembered) = try snapshot()
            try turnOn(query, active: active, remembered: remembered)
        case let .toggle(query):
            try store.lock()
            let (active, remembered) = try snapshot()
            if active.contains(where: { !$0.builtIn && $0.matches(query) }) {
                try turnOff(query, active: active, remembered: remembered)
            } else {
                try turnOn(query, active: active, remembered: remembered)
            }
        }
    }

    /// Reads the displays that are on and the ones screens turned off, dropping remembered
    /// displays that are on again (replugged, or brought back by another tool).
    private func snapshot() throws -> (active: [Display], remembered: [Display]) {
        let active = try Displays.active()
        return (active, removingActive(try store.load(), active: active))
    }

    private func turnOff(_ query: String?, active: [Display], remembered: [Display]) throws {
        let targets = active.filter { !$0.builtIn && $0.matches(query) }
        guard !targets.isEmpty else {
            return try explainNothingToTurnOff(query, active: active, remembered: remembered)
        }
        guard active.count > targets.count else {
            throw Failure(description: "turning off \(names(targets)) would leave no display on")
        }
        let written = remembered.filter { entry in !targets.contains { $0.isSame(as: entry) } } + targets
        try store.save(written)
        let outcome = apply(enabled: false, to: targets)
        if let now = try? Displays.active() { try store.save(removingActive(written, active: now)) }
        try report(outcome, verb: "off")
    }

    private func turnOn(_ query: String?, active: [Display], remembered: [Display]) throws {
        let targets = remembered.filter { $0.matches(query) }
        guard !targets.isEmpty else {
            return try explainNothingToTurnOn(query, active: active)
        }
        let outcome = apply(enabled: true, to: targets)
        let kept = remembered.filter { entry in !outcome.changed.contains { $0.isSame(as: entry) } }
        try store.save(removingActive(kept, active: (try? Displays.active()) ?? []))
        try report(outcome, verb: "on")
    }

    private func status(json: Bool) throws {
        let active = try Displays.active()
        let off = removingActive(try store.load(), active: active)
        let rows = (active.map { row($0, on: true) } + off.map { row($0, on: false) }).sorted { $0.id < $1.id }
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(rows), as: UTF8.self))
            return
        }
        let idWidth = rows.map { String($0.id).count }.max() ?? 0
        let nameWidth = rows.map(\.name.count).max() ?? 0
        let sizes = rows.map { row in row.width.map { "\($0)x\(row.height ?? 0)" } ?? "" }
        let sizeWidth = sizes.map(\.count).max() ?? 0
        for (row, size) in zip(rows, sizes) {
            let hertz = row.hertz.map { $0 > 0 ? "\($0) Hz" : "" } ?? ""
            let tags = [row.main ? "main" : nil, row.builtIn ? "built-in" : nil].compactMap { $0 }.joined(separator: ", ")
            let line = [
                padded(row.state, 3), padded(String(row.id), idWidth), padded(row.name, nameWidth),
                padded(size, sizeWidth), padded(hertz, 6), tags,
            ].joined(separator: "  ")
            print(line.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Turns each display on or off in a transaction of its own and waits until macOS shows the
    /// change. Several displays in one transaction take seconds each and settle out of order.
    private func apply(enabled: Bool, to displays: [Display]) -> Outcome {
        var outcome = Outcome()
        for display in displays {
            do {
                try Displays.setEnabled(enabled, id: display.id)
            } catch DisplayError.configuration(_, let error) where enabled {
                outcome.failed.append("could not turn on \(display.name): probably unplugged (CGError \(error.rawValue)); plug it in and run `screens on` again")
                continue
            } catch {
                outcome.failed.append("could not turn \(enabled ? "on" : "off") \(display.name): \(error)")
                continue
            }
            if Displays.waitUntil({ $0.contains(display.id) == enabled }) {
                outcome.changed.append(display)
            } else {
                outcome.failed.append("\(display.name) did not turn \(enabled ? "on" : "off") within 20 s; check `screens status`")
            }
        }
        return outcome
    }

    /// Prints what changed and throws the failures, so a partial run still says what it did.
    private func report(_ outcome: Outcome, verb: String) throws {
        if !outcome.changed.isEmpty { print("\(verb): \(names(outcome.changed))") }
        guard outcome.failed.isEmpty else { throw Failure(description: outcome.failed.joined(separator: "\n")) }
    }

    /// Says why `off` had nothing to do: already off is fine, a name that matches nothing is not.
    private func explainNothingToTurnOff(_ query: String?, active: [Display], remembered: [Display]) throws {
        guard let query else { return print("no external display is on") }
        let alreadyOff = remembered.filter { $0.matches(query) }
        if !alreadyOff.isEmpty { return print("already off: \(names(alreadyOff))") }
        if active.contains(where: { $0.builtIn && $0.matches(query) }) {
            throw Failure(description: "screens never turns off the built-in display")
        }
        throw Failure(description: "no display matches \"\(query)\"")
    }

    /// Says why `on` had nothing to do: already on is fine, a name that matches nothing is not.
    private func explainNothingToTurnOn(_ query: String?, active: [Display]) throws {
        guard let query else { return print("no display was turned off by screens") }
        let alreadyOn = active.filter { $0.matches(query) }
        if !alreadyOn.isEmpty { return print("already on: \(names(alreadyOn))") }
        throw Failure(description: "no display matches \"\(query)\"")
    }

    /// Drops remembered displays that are on, matched by UUID so a display back under a new ID counts.
    private func removingActive(_ remembered: [Display], active: [Display]) -> [Display] {
        remembered.filter { entry in !active.contains { $0.isSame(as: entry) } }
    }

    /// Builds a status row, reading main display and mode only for displays that are on.
    private func row(_ display: Display, on: Bool) -> Row {
        let mode = on ? Displays.mode(of: display.id) : nil
        return Row(
            id: display.id, uuid: display.uuid, name: display.name, state: on ? "on" : "off",
            builtIn: display.builtIn, main: on && Displays.isMain(display.id),
            width: mode?.width, height: mode?.height, hertz: mode?.hertz
        )
    }

    /// Joins display names for a one-line report.
    private func names(_ displays: [Display]) -> String {
        displays.map(\.name).joined(separator: ", ")
    }

    /// Pads text with spaces to a column width without ever cutting it short.
    private func padded(_ text: String, _ width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }
}
