import CoreGraphics
import Foundation

enum StoreError: Error, CustomStringConvertible {
    case lock(URL, Int32)
    case unreadable(URL)

    var description: String {
        switch self {
        case let .lock(url, code):
            "could not lock \(url.path) (\(String(cString: strerror(code))))"
        case let .unreadable(aside):
            "the list of displays screens turned off was unreadable and moved to \(aside.path); those displays come back at logout or restart"
        }
    }
}

struct DisabledStore {
    private struct Contents: Codable {
        let session: String
        let displays: [Display]
    }

    let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("screens/disabled.json")
    }

    /// Holds an exclusive lock until the process exits, so two overlapping runs (a double-tapped
    /// shortcut) take turns instead of overwriting each other's list.
    func lock() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.deletingLastPathComponent().appendingPathComponent(".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else { throw StoreError.lock(lockURL, errno) }
    }

    func load() throws -> [Display] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let contents = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: url))
            guard contents.session == Self.currentSession() else {
                try? FileManager.default.removeItem(at: url)
                return []
            }
            return contents.displays
        } catch {
            let aside = url.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: url, to: aside)
            throw StoreError.unreadable(aside)
        }
    }

    func save(_ displays: [Display]) throws {
        guard !displays.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contents = Contents(session: Self.currentSession(), displays: displays)
        try encoder.encode(contents).write(to: url, options: .atomic)
    }

    /// Identifies the login session. Displays are turned off only until logout, so a list written
    /// in an earlier session describes displays that are already back on.
    private static func currentSession() -> String {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if let uuid = session?["CGSSessionUniqueSessionUUID"] as? String { return uuid }
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return "\(boot.tv_sec)-\(session?["kCGSSessionAuditIDKey"] ?? "")"
    }
}
