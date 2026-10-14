// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// The UserDefaults keys of the spec, section 10. Nothing else is stored in preferences.
@MainActor
enum Settings {
    static let defaults = UserDefaults.standard
    static let macFiguresInBar = "macFiguresInBar"
    static let nudges = "nudges"
    static let listPriceEquivalent = "listPriceEquivalent"
    static let hookPreviousCommand = "hookPreviousCommand"
    static let nudgedWeeklyWindow = "nudgedWeeklyWindow"
    static let nudgedFiveHourWindow = "nudgedFiveHourWindow"

    static func register() {
        defaults.register(defaults: [macFiguresInBar: false, nudges: true, listPriceEquivalent: true])
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func set(_ key: String, _ value: Bool) { defaults.set(value, forKey: key) }
    static func toggle(_ key: String) { set(key, !bool(key)) }

    static func nudged(_ key: String) -> Double? {
        defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
    }
    static func setNudged(_ key: String, _ epoch: Double) { defaults.set(epoch, forKey: key) }
}

enum Paths {
    static let bundleId = "dev.tokenpanda.app"
    static var dataDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleId, isDirectory: true)
    }
    static var settingsJSON: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    static var weeksFile: URL { dataDir.appendingPathComponent("weeks.json") }
}
