// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import UserNotifications

/// The two nudges through the macOS notification centre. UNUserNotificationCenter needs an app bundle; from a bare
/// executable (swift run) the centre cannot be created, so the notifier stays silent and says so.
@MainActor
final class Notifier {
    enum State { case unavailable, undecided, allowed, denied }
    private(set) var state: State = .undecided
    private let available: Bool

    init() {
        available = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
        if !available { state = .unavailable }
    }

    var noteForSettings: String? {
        switch state {
        case .denied: return "Notifications are off for this app in System Settings"
        case .unavailable: return "Notifications need the app bundle, not swift run"
        default: return nil
        }
    }

    func requestIfNeeded() {
        guard available, state == .undecided else { return }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional: state = .allowed
            case .denied: state = .denied
            default:
                let ok = (try? await center.requestAuthorization(options: [.alert])) ?? false
                state = ok ? .allowed : .denied
            }
        }
    }

    func post(title: String, body: String, id: String) {
        guard available, state == .allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
