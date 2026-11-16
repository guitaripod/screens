import AppKit
import CoreGraphics
import Foundation

struct Display: Codable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let builtIn: Bool
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32

    func matches(_ query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query) || String(id) == query
    }
}

enum DisplayError: Error, CustomStringConvertible {
    case skyLightUnavailable
    case configuration(String, CGError)

    var description: String {
        switch self {
        case .skyLightUnavailable:
            "SLSConfigureDisplayEnabled is missing from SkyLight on this macOS"
        case let .configuration(step, error):
            "\(step) failed with CGError \(error.rawValue)"
        }
    }
}

enum Displays {
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    static func active() -> [Display] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let names = screenNames()
        return ids.prefix(Int(count)).map { id in
            Display(
                id: id,
                name: names[id] ?? "Display \(id)",
                builtIn: CGDisplayIsBuiltin(id) != 0,
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id)
            )
        }
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
        while Date() < deadline {
            if condition(Set(active().map(\.id))) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition(Set(active().map(\.id)))
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
