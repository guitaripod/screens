enum Command: Equatable {
    case toggle(String?)
    case off(String?)
    case on(String?)
    case status(json: Bool)
    case version
    case help

    static let usage = """
    usage: screens [name]
           screens off [name]
           screens on [name]
           screens status [--json]

      screens          turn the external displays off, or back on when none is on
      screens <name>   the same for just the displays matching <name>
      off [name]       turn off every external display, or the matching ones
      on [name]        turn back on what screens turned off, or the matching ones
      status           list displays with their state, resolution and refresh rate

    A name matches any part of a display's name, ignoring case, or its exact id from
    `screens status`; use the id when a name matches too much or is a command word.
    Words after the command are joined, so `screens off lg tv` matches "LG TV".

    The built-in display and the last display that is on are never turned off.
    Displays turned off come back with `screens on`, or at logout or restart.

    Exit status: 0 done or nothing to do, 1 a display could not be changed or no
    display matches, 2 usage error. Also: toggle, list, help, --version.
    """

    static func parse(_ arguments: [String]) -> Command? {
        guard let first = arguments.first else { return .toggle(nil) }
        let rest = Array(arguments.dropFirst())
        let query = rest.isEmpty ? nil : rest.joined(separator: " ")
        switch first {
        case "toggle": return .toggle(query)
        case "off": return .off(query)
        case "on": return .on(query)
        case "status", "list":
            if rest.isEmpty { return .status(json: false) }
            return rest == ["--json"] ? .status(json: true) : nil
        case "version", "--version", "-V": return rest.isEmpty ? .version : nil
        case "help", "--help", "-h": return rest.isEmpty ? .help : nil
        default: return first.hasPrefix("-") ? nil : .toggle(arguments.joined(separator: " "))
        }
    }
}
