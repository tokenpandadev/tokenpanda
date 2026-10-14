import Foundation

// The status line hook: the script as a resource, installed only on an explicit click, chaining an existing command.
// settings.json is otherwise off limits: this file reads the one statusLine key and changes the one statusLine key.

public enum HookScript {
    /// The script text, identical to hook/statusline.sh in the repository (a test checks that).
    public static let template = """
    #!/bin/sh
    # The status line hook. Copies the feed Claude Code hands it to one file per session, atomically,
    # then hands the same input to the status line command that was configured before, if any.
    # It parses nothing and needs nothing but sh. The app fills in DIR and PREV at install time.
    DIR="__DIR__"
    PREV='__PREV__'
    input=$(cat)
    sid=$(printf '%s' "$input" | sed -n 's/.*"session_id":"\\([0-9a-fA-F-]*\\)".*/\\1/p' | head -n 1)
    mkdir -p "$DIR"
    if [ -n "$sid" ]; then
      printf '%s' "$input" > "$DIR/$sid.json.tmp" && mv -f "$DIR/$sid.json.tmp" "$DIR/$sid.json"
    else
      printf '%s' "$input" > "$DIR/latest.json.tmp" && mv -f "$DIR/latest.json.tmp" "$DIR/latest.json"
    fi
    if [ -n "$PREV" ]; then printf '%s' "$input" | sh -c "$PREV"; fi
    exit 0

    """

    /// The script with DIR and PREV filled in. PREV is single quoted for sh.
    public static func render(sessionsDir: String, previousCommand: String?) -> String {
        let prev = (previousCommand ?? "").replacingOccurrences(of: "'", with: "'\\''")
        return template
            .replacingOccurrences(of: "__DIR__", with: sessionsDir.replacingOccurrences(of: "\"", with: "\\\""))
            .replacingOccurrences(of: "__PREV__", with: prev)
    }
}

public struct HookStatus: Sendable, Equatable {
    public var installed: Bool
    public var previousCommand: String?   // a status line command that is not ours, when one exists
    public init(installed: Bool, previousCommand: String?) { self.installed = installed; self.previousCommand = previousCommand }
}

public enum HookError: Error, Sendable, CustomStringConvertible {
    case cannotReadSettings(String)
    case cannotWriteSettings(String)
    case cannotWriteScript(String)

    public var description: String {
        switch self {
        case .cannotReadSettings(let m): return "cannot read settings.json: " + m
        case .cannotWriteSettings(let m): return "cannot write settings.json: " + m
        case .cannotWriteScript(let m): return "cannot write the hook script: " + m
        }
    }
}

public struct Hook: Sendable {
    public let settingsURL: URL
    public let dataDir: URL
    public var hookPath: URL { dataDir.appendingPathComponent("hook.sh") }
    /// The statusLine object as it was before install, so uninstall can put it back exactly. {} when there was none.
    public var backupPath: URL { dataDir.appendingPathComponent("statusline-before.json") }
    /// The statusLine command runs in a shell, so the path is single quoted; Application Support has a space in it.
    public var hookCommand: String { "'" + hookPath.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public var sessionsDir: URL { dataDir.appendingPathComponent("sessions", isDirectory: true) }
    public static let refreshInterval = 5

    public init(settingsURL: URL, dataDir: URL) { self.settingsURL = settingsURL; self.dataDir = dataDir }

    func isOurs(_ command: String) -> Bool { command == hookCommand || command == hookPath.path }

    /// Reads the one statusLine key. Anything else in settings.json stays unread.
    public func status() -> HookStatus {
        guard let obj = readSettings(), let sl = obj["statusLine"] as? [String: Any], let cmd = sl["command"] as? String else {
            return HookStatus(installed: false, previousCommand: nil)
        }
        if isOurs(cmd) { return HookStatus(installed: true, previousCommand: nil) }
        return HookStatus(installed: false, previousCommand: cmd)
    }

    /// The modification time of settings.json, so a caller can re-read it only when it changed. nil when it does not exist.
    public func settingsModified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: settingsURL.path))?[.modificationDate] as? Date
    }

    func readSettings() -> [String: Any]? {
        guard let d = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// The statusLine object saved at install. nil: no backup file. .some(nil): there was no statusLine before.
    func readBackup() -> [String: Any]?? {
        guard let d = try? Data(contentsOf: backupPath), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return .some(obj["statusLine"] as? [String: Any])
    }

    func writeBackup(_ statusLine: [String: Any]?) throws {
        let obj: [String: Any] = statusLine.map { ["statusLine": $0] } ?? [:]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: backupPath, options: .atomic)
    }

    /// Writes the script and the statusLine entry. Only ever called from an install row's click.
    /// An existing statusLine keeps its other keys (padding, refreshInterval and the like); only type and command change,
    /// and refreshInterval is added when there was none.
    public func install() throws -> HookStatus {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsURL.path) {
            guard let s = readSettings() else { throw HookError.cannotReadSettings("settings.json is not a JSON object") }
            settings = s
        }
        let existing = settings["statusLine"] as? [String: Any]
        let existingCommand = existing?["command"] as? String
        let alreadyOurs = existingCommand.map(isOurs) ?? false
        // a reinstall chains what was there before the first install, kept in the backup
        let before: [String: Any]? = alreadyOurs ? (readBackup() ?? nil) : existing
        var previous = before?["command"] as? String
        if let p = previous, isOurs(p) { previous = nil }
        let script = HookScript.render(sessionsDir: sessionsDir.path, previousCommand: previous)
        do {
            try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
            try script.write(to: hookPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath.path)
            if !alreadyOurs { try writeBackup(existing) }
        } catch { throw HookError.cannotWriteScript(error.localizedDescription) }
        var sl = existing ?? [:]
        sl["type"] = "command"
        sl["command"] = hookCommand
        if sl["refreshInterval"] == nil { sl["refreshInterval"] = Hook.refreshInterval }
        settings["statusLine"] = sl
        try writeSettings(settings)
        return HookStatus(installed: true, previousCommand: previous)
    }

    /// Puts the statusLine object back as it was before install, or removes the key when there was none.
    /// Touches settings.json only while the entry is still ours; a statusLine the user changed since stays as it is.
    /// previousCommand is the fallback when the backup file is missing. The script, the backup and the sessions folder are removed.
    public func uninstall(previousCommand: String?) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: settingsURL.path) {
            guard var settings = readSettings() else { throw HookError.cannotReadSettings("settings.json is not a JSON object") }
            let current = settings["statusLine"] as? [String: Any]
            if let cmd = current?["command"] as? String, isOurs(cmd) {
                if let backup = readBackup() {
                    if let before = backup { settings["statusLine"] = before } else { settings.removeValue(forKey: "statusLine") }
                } else if let previousCommand, var sl = current {
                    sl["command"] = previousCommand
                    settings["statusLine"] = sl
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try writeSettings(settings)
            }
        }
        try? fm.removeItem(at: sessionsDir)
        try? fm.removeItem(at: hookPath)
        try? fm.removeItem(at: backupPath)
    }

    /// The system JSON writer re-serialises the file: pretty printed with slashes unescaped; indentation and key order may change.
    /// In content only the statusLine key differs.
    func writeSettings(_ settings: [String: Any]) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: settingsURL, options: .atomic)
        } catch { throw HookError.cannotWriteSettings(error.localizedDescription) }
    }
}
