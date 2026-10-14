// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import os
import Text
import Pace
import Feed
import Transcripts
import MacStats
import UI

/// The keys the popover handles, by their virtual key code.
enum KeyCode {
    static let escape: UInt16 = 53
    static let tab: UInt16 = 48
}

/// The thresholds of the nudges and of the Mac warning.
enum Rules {
    static let weeklyNudgeAt = 80.0                           // percent of the weekly window
    static let fiveHourNudgeLead: TimeInterval = 15 * 60      // before the 5h window resets
    static let hogSustained: TimeInterval = 60                // one process over the hog threshold this long
    static let pressureWarn = 2                               // kern.memorystatus_vm_pressure_level: 2 warn, 4 critical
}

/// The main actor state: the status item, the popover, the timers, and the readers it asks.
@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let feed: FeedReader
    let hook: Hook
    let store: TranscriptStore
    let sampler = MacSampler()
    let notifier = Notifier()

    var feedState = FeedState()
    var hookStatus = HookStatus(installed: false, previousCommand: nil)
    var hookError: String? = nil
    var settingsModified: Date? = nil   // settings.json is read again only when this moves
    let log = Logger(subsystem: Paths.bundleId, category: "hook")
    var tokens: TokenSummary? = nil
    var transcriptsRootsExist = true
    var transcriptsError: String? = nil
    var mac: MacSample? = nil
    var weeks = WeekRecords()
    var hogPid: Int32? = nil
    var hogSince: Date? = nil
    var tab = 0
    var section = 0
    var lastItem: ItemState? = nil
    var lastScreen: Screen? = nil
    var transcriptsVersion = -1
    var tokensDay: Date? = nil

    var item: NSStatusItem!
    let popover = NSPopover()
    let lineView = LineView()
    var keyMonitor: Any?
    var feedTimer: DispatchSourceTimer?
    var macTimer: DispatchSourceTimer?
    var transcriptTimer: DispatchSourceTimer?
    var dirSource: DispatchSourceFileSystemObject?
    var dirFD: Int32 = -1
    let queue = DispatchQueue(label: "dev.tokenpanda.timers", qos: .utility)
    var transcriptsBusy = false

    override init() {
        feed = FeedReader(dataDir: Paths.dataDir)
        hook = Hook(settingsURL: Paths.settingsJSON, dataDir: Paths.dataDir)
        store = TranscriptStore(roots: TranscriptLocator.roots())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        weeks = WeekRecords.load(from: Paths.weeksFile)
        try? FileManager.default.createDirectory(at: feed.sessionsDir, withIntermediateDirectories: true)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("Claude usage")

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        let tint = NSView(); tint.wantsLayer = true; tint.layer?.backgroundColor = Tokens.tint.ns.cgColor
        root.addSubview(tint)
        root.addSubview(lineView)
        // pinned to the root on all four edges: the popover shrinks and grows while open as lines come and go,
        // and an autoresized view in the non flipped root kept its old height and slid up out of the frame
        for v in [tint, lineView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                v.topAnchor.constraint(equalTo: root.topAnchor), v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        let vc = NSViewController(); vc.view = root
        popover.contentViewController = vc
        lineView.onAction = { [weak self] a in self?.perform(a) }

        readHookStatus()
        if Settings.bool(Settings.nudges) { notifier.requestIfNeeded() }
        startFeedWatch()
        startTimers(open: false)
        Task { await refreshFeed(); await refreshTranscripts(); await sampleMac(full: false) }

        #if DEBUG
        // debug flag: after 45 s, open the popover and write the three live tabs to PNG (for the CPU measurement)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--live-snapshot"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(45))
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if !popover.isShown { togglePopover() }
                try? await Task.sleep(for: .seconds(5))   // one full sample with the popover open
                for t in 0..<3 {
                    var i = input; i.tab = t
                    try? SnapshotWriter.writeScreen(ScreenBuilder.screen(i), to: dir.appendingPathComponent("live-tab\(t).png"))
                }
                try? SnapshotWriter.writeItem(ScreenBuilder.item(input), to: dir.appendingPathComponent("live-item.png"))
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        feedTimer?.cancel(); macTimer?.cancel(); transcriptTimer?.cancel(); dirSource?.cancel()
    }

    // MARK: timers

    func timer(_ seconds: Double, _ body: @escaping @Sendable () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + seconds, repeating: seconds, leeway: .milliseconds(Int(seconds * 100)))
        t.setEventHandler(handler: body)
        t.resume()
        return t
    }

    func startTimers(open: Bool) {
        macTimer?.cancel(); transcriptTimer?.cancel(); feedTimer?.cancel()
        feedTimer = timer(5) { Task { @MainActor in await self.refreshFeed() } }
        macTimer = timer(open ? 2 : 10) { Task { @MainActor in await self.sampleMac(full: open) } }
        transcriptTimer = timer(open ? 10 : 300) { Task { @MainActor in await self.refreshTranscripts() } }
    }

    func stopFeedWatch() {
        dirSource?.cancel()   // the cancel handler closes its descriptor
        dirSource = nil
        dirFD = -1
    }

    func startFeedWatch() {
        stopFeedWatch()
        dirFD = open(feed.sessionsDir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write], queue: queue)
        src.setEventHandler { Task { @MainActor in await self.refreshFeed() } }
        src.setCancelHandler { [fd = dirFD] in close(fd) }
        src.resume()
        dirSource = src
    }

    // MARK: readers

    func refreshFeed() async {
        let now = Date()
        feedState = await feed.scan(now: now)
        if hook.settingsModified() != settingsModified { readHookStatus() }
        if let l = feedState.limits, let w = l.windows["seven_day"] {
            var ws = weeks
            ws.apply(LimitWindow(key: "seven_day", usedPercentage: w.used, resetsAt: w.resetsAt), at: l.asOf)
            if ws != weeks { weeks = ws; weeks.save(to: Paths.weeksFile) }
        }
        checkNudges(now: now)
        render()
    }

    func refreshTranscripts() async {
        guard !transcriptsBusy else { return }
        transcriptsBusy = true
        let now = Date()
        let result = await store.refresh(now: now, onlyIfChanged: true)
        transcriptsBusy = false
        transcriptsRootsExist = result.rootsExist
        transcriptsError = result.error
        // the aggregate moves only with new records or a new day (the "today" window)
        let day = Calendar.current.startOfDay(for: now)
        if result.version != transcriptsVersion || tokensDay != day || tokens == nil {
            transcriptsVersion = result.version
            tokensDay = day
            let records = result.records
            tokens = await Task.detached(priority: .utility) { Aggregator.summarize(records, now: now) }.value
        }
        render()
    }

    /// settings.json, the one statusLine key, read at launch and again only when the file's modification time moves.
    func readHookStatus() {
        settingsModified = hook.settingsModified()
        hookStatus = hook.status()
    }

    func sampleMac(full: Bool) async {
        let s = await sampler.sample(full: full)
        mac = s
        // the hog is timed by the clock, so the rule holds at the 2 s and the 10 s cadence alike
        if let h = s.hogPid {
            if h != hogPid { hogPid = h; hogSince = Date() }
        } else {
            hogPid = nil; hogSince = nil
        }
        render()
    }

    var warning: Bool {
        guard let m = mac else { return false }
        let hog = hogSince.map { Date().timeIntervalSince($0) >= Rules.hogSustained } ?? false
        return m.pressureLevel >= Rules.pressureWarn || hog
    }

    // MARK: nudges

    func checkNudges(now: Date) {
        guard Settings.bool(Settings.nudges), let l = feedState.limits, !OpenSessionsRule.isStale(asOf: l.asOf, now: now) else { return }
        if let w = l.windows["seven_day"], let length = WindowKind.length(forKey: "seven_day"), w.used >= Rules.weeklyNudgeAt, now < w.resetsAt,
           Settings.nudged(Settings.nudgedWeeklyWindow) != w.resetsAt.timeIntervalSince1970 {
            let start = w.resetsAt.addingTimeInterval(-length)
            let body = PaceModel.reading(used: w.used, start: start, reset: w.resetsAt, now: now).map { PaceModel.nudgeBody($0) } ?? ""
            notifier.post(title: "Weekly at \(Int(w.used.rounded()))%", body: body, id: "weekly-\(Int(w.resetsAt.timeIntervalSince1970))")
            Settings.setNudged(Settings.nudgedWeeklyWindow, w.resetsAt.timeIntervalSince1970)
        }
        if let f = l.windows["five_hour"], now >= f.resetsAt.addingTimeInterval(-Rules.fiveHourNudgeLead), now < f.resetsAt,
           Settings.nudged(Settings.nudgedFiveHourWindow) != f.resetsAt.timeIntervalSince1970 {
            notifier.post(title: "5h window ends in 15 min", body: "\(Int(f.used.rounded()))% used.", id: "five-\(Int(f.resetsAt.timeIntervalSince1970))")
            Settings.setNudged(Settings.nudgedFiveHourWindow, f.resetsAt.timeIntervalSince1970)
        }
    }

    // MARK: rendering

    var input: LiveInput {
        LiveInput(feed: feedState, hook: hookStatus, tokens: tokens, transcriptsRootsExist: transcriptsRootsExist, transcriptsError: transcriptsError,
                  mac: mac, weeks: weeks, macInBar: Settings.bool(Settings.macFiguresInBar), nudges: Settings.bool(Settings.nudges),
                  listPrice: Settings.bool(Settings.listPriceEquivalent), nudgeNote: notifier.noteForSettings, hookError: hookError,
                  warn: warning, tab: tab, section: section, now: Date())
    }

    func render() {
        let i = input
        let st = ScreenBuilder.item(i)
        if st != lastItem {
            lastItem = st
            item.button?.image = ItemImage.make(st)
            item.button?.alphaValue = st.stale ? 0.5 : 1
            item.button?.setAccessibilityLabel(st.label)
        }
        if popover.isShown {
            let screen = ScreenBuilder.screen(i)
            guard screen != lastScreen else { return }
            lastScreen = screen
            let lines = Grammar.popover(screen)
            lineView.lines = lines
            let size = NSSize(width: LineView.width, height: lineView.contentHeight)
            if popover.contentSize != size { popover.contentSize = size }
        }
    }

    func perform(_ a: Action) {
        switch a {
        case .tab(let t): tab = t
        case .section(let s): section = s
        case .toggle(let key):
            Settings.toggle(key)
            if key == Settings.nudges, Settings.bool(key) { notifier.requestIfNeeded() }
        case .install:
            do {
                let st = try hook.install()
                hookError = nil
                if let p = st.previousCommand { Settings.defaults.set(p, forKey: Settings.hookPreviousCommand) }
                startFeedWatch()
            } catch {
                hookFailed("install", error)
            }
            readHookStatus()
        case .uninstall:
            do {
                try hook.uninstall(previousCommand: Settings.defaults.string(forKey: Settings.hookPreviousCommand))
                hookError = nil
                Settings.defaults.removeObject(forKey: Settings.hookPreviousCommand)
                stopFeedWatch()
            } catch {
                hookFailed("remove", error)
            }
            readHookStatus()
        case .quit: NSApp.terminate(nil)
        }
        render()
    }

    func hookFailed(_ what: String, _ error: Error) {
        let message = (error as? HookError)?.description ?? error.localizedDescription
        hookError = "Could not \(what) the entry: " + message
        log.error("status line \(what, privacy: .public) failed: \(message, privacy: .private)")
    }

    // MARK: popover

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        let screen = ScreenBuilder.screen(input)
        lastScreen = screen
        lineView.lines = Grammar.popover(screen)
        popover.contentSize = NSSize(width: LineView.width, height: lineView.contentHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeFirstResponder(lineView)
        startTimers(open: true)
        Task { await sampleMac(full: true); await refreshTranscripts() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e) ? nil : e
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastScreen = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        startTimers(open: false)
    }

    func handleKey(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) {
            if e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return true }
            return false
        }
        switch e.keyCode {
        case KeyCode.escape: popover.performClose(nil); return true
        case KeyCode.tab: tab = (tab + (e.modifierFlags.contains(.shift) ? 2 : 1)) % 3; render(); return true
        default: break
        }
        if tab == 0, let c = e.charactersIgnoringModifiers, let i = ["m", "p", "s"].firstIndex(of: c) { section = i; render(); return true }
        return false
    }
}
