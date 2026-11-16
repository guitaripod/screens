import AppKit
import CoreGraphics
import Foundation

struct Display: Codable, Equatable {
    let id: CGDirectDisplayID
    let uuid: String?
    let name: String
    let builtIn: Bool

    func matches(_ query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query) || String(id) == query
    }

    func isSame(as other: Display) -> Bool {
        if let uuid, let otherUUID = other.uuid { return uuid == otherUUID }
        return id == other.id
    }
}

struct DisplayMode {
    let width: Int
    let height: Int
    let hertz: Int
}

enum DisplayError: Error, CustomStringConvertible {
    case skyLightUnavailable
    case listUnavailable(CGError)
    case configuration(String, CGError)

    var description: String {
        switch self {
        case .skyLightUnavailable:
            "SLSConfigureDisplayEnabled is missing from SkyLight on this macOS"
        case let .listUnavailable(error):
            "CGGetActiveDisplayList failed (CGError \(error.rawValue))"
        case let .configuration(step, error):
            "\(step) failed (CGError \(error.rawValue))"
        }
    }
}

enum Displays {
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    static func active() throws -> [Display] {
        let names = screenNames()
        return try activeIDs().map { id in
            Display(id: id, uuid: uuid(of: id), name: names[id] ?? "Display \(id)", builtIn: CGDisplayIsBuiltin(id) != 0)
        }
    }

    static func isMain(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsMain(id) != 0
    }

    static func mode(of id: CGDirectDisplayID) -> DisplayMode? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        return DisplayMode(width: mode.pixelWidth, height: mode.pixelHeight, hertz: Int(mode.refreshRate.rounded()))
    }

    static func setEnabled(_ enabled: Bool, id: CGDirectDisplayID) throws {
        let configure = try skyLightConfigure()
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { throw DisplayError.configuration("CGBeginDisplayConfiguration", begin) }
        let result = configure(config, id, enabled)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.configuration("SLSConfigureDisplayEnabled", result)
        }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else { throw DisplayError.configuration("CGCompleteDisplayConfiguration", complete) }
    }

    static func waitUntil(timeout: TimeInterval = 20, _ condition: (Set<CGDirectDisplayID>) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let ids = try? activeIDs(), condition(Set(ids)) { return true }
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Lists the displays that are drawing, sized from the count CoreGraphics reports. A disabled
    /// display is missing from this list and from the online list alike.
    private static func activeIDs() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var error = CGGetActiveDisplayList(0, nil, &count)
        guard error == .success else { throw DisplayError.listUnavailable(error) }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        error = CGGetActiveDisplayList(count, &ids, &count)
        guard error == .success else { throw DisplayError.listUnavailable(error) }
        return Array(ids.prefix(Int(count)))
    }

    /// The display's UUID, which survives a display coming back under a new ID. CoreGraphics only
    /// knows it while the display is on.
    private static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Loads the private SkyLight call that adds or removes a display from the WindowServer's
    /// configuration, the same thing that happens when a cable is pulled or plugged back in.
    private static func skyLightConfigure() throws -> ConfigureEnabled {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let symbol = dlsym(handle, "SLSConfigureDisplayEnabled")
        else { throw DisplayError.skyLightUnavailable }
        return unsafeBitCast(symbol, to: ConfigureEnabled.self)
    }

    /// Maps display IDs to the names macOS shows in System Settings, read from NSScreen.
    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            names[number.uint32Value] = screen.localizedName
        }
        return names
    }
}
