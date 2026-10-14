// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import Feed

/// The feed parser against the two shapes seen (integer percentages, the doc's 23.5), the first call rule,
/// the open sessions timing, and the hook script.
struct FeedTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func capturedShapeParses() throws {
        let s = try #require(SnapshotParser.parse(try fixture("feed-sample"), writtenAt: Date(timeIntervalSince1970: 1791900924)))
        #expect(s.sessionId == "3f1a9c2e-0000-4000-8000-000000000001")
        #expect(s.projectName == "workspace")
        #expect(s.modelDisplayName == "Fable 5.1")
        #expect(s.modelId == "claude-fable-5-1")
        #expect(s.effortLevel == "high")
        #expect(s.contextWindowSize == 1_000_000)
        #expect(s.contextUsedPercentage == 4)
        #expect(s.currentUsageTokens == 2 + 4 + 17266 + 27543)
        #expect(abs((s.totalCostUSD!) - (0.35242575)) <= 1e-9)
        #expect(s.linesAdded == 0)
        #expect(s.rateLimits?["five_hour"] == LimitWindow(key: "five_hour", usedPercentage: 31, resetsAt: Date(timeIntervalSince1970: 1791909600)))
        #expect(s.rateLimits?["seven_day"]?.usedPercentage == 13)
        #expect(s.rateLimits?.count == 2)   // scratchpad_dir and every other key is ignored
    }

    @Test func docExampleParsesFractionalPercent() throws {
        let s = try #require(SnapshotParser.parse(try fixture("feed-doc"), writtenAt: Date()))
        #expect(s.rateLimits?["five_hour"]?.usedPercentage == 23.5)
        #expect(s.rateLimits?["seven_day"]?.usedPercentage == 67.3)
        #expect(s.rateLimits?["spend_limit"] == nil)
    }

    @Test func firstCallHasNoLimitsAndNullUsage() throws {
        let s = try #require(SnapshotParser.parse(try fixture("feed-first"), writtenAt: Date()))
        #expect(s.rateLimits == nil)
        #expect(s.currentUsageTokens == nil)
        #expect(s.contextUsedPercentage == nil)
    }

    @Test func garbageIsNil() {
        #expect(SnapshotParser.parse(Data("not json".utf8), writtenAt: Date()) == nil)
        #expect(SnapshotParser.parse(Data("{\"no\":\"session\"}".utf8), writtenAt: Date()) == nil)
    }

    // MARK: the reader

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tokenpanda-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return url
    }

    func write(_ name: String, _ data: Data, in dir: URL, age: TimeInterval, now: Date) throws {
        let url = dir.appendingPathComponent("sessions/\(name).json")
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    @Test func firstCallLeavesWindowsUntouched() async throws {
        let dir = try tempDir()
        let now = Date()
        let reader = FeedReader(dataDir: dir)
        try write("a", try fixture("feed-first"), in: dir, age: 1, now: now)
        var st = await reader.scan(now: now)
        #expect(st.limits == nil)
        #expect(st.sessions.count == 1)
        try write("a", try fixture("feed-sample"), in: dir, age: 0.5, now: now.addingTimeInterval(2))
        st = await reader.scan(now: now.addingTimeInterval(2))
        #expect(st.limits?.windows["seven_day"]?.used == 13)
        // a later first call of another session carries nothing and changes nothing
        try write("b", try fixture("feed-first"), in: dir, age: 0, now: now.addingTimeInterval(4))
        st = await reader.scan(now: now.addingTimeInterval(4))
        #expect(st.limits?.windows["seven_day"]?.used == 13)
        #expect(st.sessions.count == 2)
        // the limits survive a new reader: they are persisted without any path or id
        let again = FeedReader(dataDir: dir)
        let st2 = await again.scan(now: now.addingTimeInterval(5))
        #expect(st2.limits?.windows["five_hour"]?.used == 31)
        let persisted = try String(contentsOf: dir.appendingPathComponent("limits.json"), encoding: .utf8)
        #expect(!(persisted.contains("workspace")))
        #expect(!(persisted.contains("3f1a9c2e")))
    }

    @Test func openSessionsTiming() async throws {
        let dir = try tempDir()
        let now = Date()
        let reader = FeedReader(dataDir: dir)
        try write("nine", try fixture("feed-sample"), in: dir, age: 9, now: now)
        try write("eleven", try fixture("feed-sample"), in: dir, age: 11, now: now)
        try write("sixtyone", try fixture("feed-sample"), in: dir, age: 61, now: now)
        let st = await reader.scan(now: now)
        #expect(st.sessions.count == 1)
        #expect(!(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sessions/sixtyone.json").path)))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sessions/eleven.json").path))
        #expect(st.isLive(now: now))
        #expect(!(st.isLive(now: now.addingTimeInterval(70))))
        #expect(OpenSessionsRule.isOpen(writtenAt: now.addingTimeInterval(-9), now: now))
        #expect(!(OpenSessionsRule.isOpen(writtenAt: now.addingTimeInterval(-11), now: now)))
        #expect(OpenSessionsRule.shouldDelete(writtenAt: now.addingTimeInterval(-61), now: now))
        #expect(!(OpenSessionsRule.shouldDelete(writtenAt: now.addingTimeInterval(-59), now: now)))
        #expect(OpenSessionsRule.isStale(asOf: now.addingTimeInterval(-3601), now: now))
        #expect(!(OpenSessionsRule.isStale(asOf: now.addingTimeInterval(-3599), now: now)))
    }

    @Test func staleAndResetPassedComeFromTheLimits() async throws {
        let dir = try tempDir()
        let now = Date(timeIntervalSince1970: 1791900924)
        let reader = FeedReader(dataDir: dir)
        try write("a", try fixture("feed-sample"), in: dir, age: 0, now: now)
        let st = await reader.scan(now: now)
        let l = try #require(st.limits)
        #expect(!(OpenSessionsRule.isStale(asOf: l.asOf, now: now.addingTimeInterval(3000))))
        #expect(OpenSessionsRule.isStale(asOf: l.asOf, now: now.addingTimeInterval(4000)))
        let five = try #require(l.windows["five_hour"])
        #expect(now.addingTimeInterval(4 * 3600) >= five.resetsAt)    // the 5h window has rolled by then
        #expect(!(now.addingTimeInterval(4 * 3600) >= l.windows["seven_day"]!.resetsAt))
    }

    // MARK: the hook script

    @Test func embeddedScriptMatchesTheFile() throws {
        let here = URL(fileURLWithPath: #filePath)
        let repo = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: repo.appendingPathComponent("hook/statusline.sh"), encoding: .utf8)
        #expect(file.trimmingCharacters(in: .whitespacesAndNewlines) == HookScript.template.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func renderedScriptQuotesThePreviousCommand() {
        let s = HookScript.render(sessionsDir: "/tmp/x y/sessions", previousCommand: "echo 'hi' | cat")
        #expect(s.contains("DIR=\"/tmp/x y/sessions\""))
        #expect(s.contains("PREV='echo '\\''hi'\\'' | cat'"))
        #expect(!(s.contains("__DIR__")))
        #expect(HookScript.render(sessionsDir: "/d", previousCommand: nil).contains("PREV=''"))
    }

    @Test func hookScriptWritesOneFilePerSession() throws {
        // the script itself, run by sh against a temp folder: the feed lands as <session_id>.json, atomically
        let dir = try tempDir()
        let script = dir.appendingPathComponent("hook.sh")
        try HookScript.render(sessionsDir: dir.appendingPathComponent("sessions").path, previousCommand: "cat > /dev/null; echo CHAINED").write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe
        try p.run()
        inPipe.fileHandleForWriting.write(try fixture("feed-sample"))
        inPipe.fileHandleForWriting.closeFile()
        p.waitUntilExit()
        let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "CHAINED")
        let written = dir.appendingPathComponent("sessions/3f1a9c2e-0000-4000-8000-000000000001.json")
        #expect(FileManager.default.fileExists(atPath: written.path))
        // $(cat) drops the trailing newline of the feed; the JSON itself is written as received
        let roundTrip = try Data(contentsOf: written), original = try fixture("feed-sample")
        #expect(roundTrip == original.prefix(while: { $0 != 0x0A }))
    }

    @Test func hookStatusReadsOnlyTheStatusLineKey() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        let hook = Hook(settingsURL: settings, dataDir: dir)
        #expect(hook.status() == HookStatus(installed: false, previousCommand: nil))
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"/usr/local/bin/other\"},\"other\":1}".write(to: settings, atomically: true, encoding: .utf8)
        #expect(hook.status() == HookStatus(installed: false, previousCommand: "/usr/local/bin/other"))
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(hook.hookPath.path)\"}}".write(to: settings, atomically: true, encoding: .utf8)
        #expect(hook.status() == HookStatus(installed: true, previousCommand: nil))
    }

    @Test func installChainsAndUninstallRestoresInATempSettingsFile() throws {
        // against a temp settings.json only; the real ~/.claude/settings.json is never touched by the tests
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"/usr/local/bin/other\"},\"model\":\"x\"}".write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir)
        let st = try hook.install()
        #expect(st == HookStatus(installed: true, previousCommand: "/usr/local/bin/other"))
        let obj = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? [String: Any])
        #expect(obj["model"] as? String == "x")
        let sl = try #require(obj["statusLine"] as? [String: Any])
        #expect(sl["command"] as? String == "'" + hook.hookPath.path + "'")
        #expect(hook.status().installed)
        #expect(sl["refreshInterval"] as? Int == 5)
        let script = try String(contentsOf: hook.hookPath, encoding: .utf8)
        #expect(script.contains("PREV='/usr/local/bin/other'"))
        try hook.uninstall(previousCommand: st.previousCommand)
        let back = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? [String: Any])
        #expect((back["statusLine"] as? [String: Any])?["command"] as? String == "/usr/local/bin/other")
        #expect(back["model"] as? String == "x")
    }

    @Test func installKeepsTheOtherStatusLineKeysAndUninstallRestoresTheObjectExactly() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        let original = "{\"statusLine\":{\"type\":\"command\",\"command\":\"~/bin/line.sh\",\"padding\":2,\"refreshInterval\":10},\"env\":{\"A\":\"https://example.com/x\"}}"
        try original.write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir)
        let st = try hook.install()
        #expect(st.previousCommand == "~/bin/line.sh")
        let text = try String(contentsOf: settings, encoding: .utf8)
        #expect(!(text.contains("\\/")))                 // slashes are written as they are
        let obj = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let sl = try #require(obj["statusLine"] as? [String: Any])
        #expect(sl["padding"] as? Int == 2)
        #expect(sl["refreshInterval"] as? Int == 10)       // the user's interval is kept
        #expect(sl["command"] as? String == hook.hookCommand)
        #expect((obj["env"] as? [String: Any])?["A"] as? String == "https://example.com/x")
        // a second click does not chain the hook to itself and keeps the first backup
        let again = try hook.install()
        #expect(again.previousCommand == "~/bin/line.sh")
        #expect(try String(contentsOf: hook.hookPath, encoding: .utf8).contains("PREV='~/bin/line.sh'"))
        try hook.uninstall(previousCommand: nil)
        let back = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? NSDictionary)
        let before = try #require(JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary)
        #expect(back == before)
        #expect(!(FileManager.default.fileExists(atPath: hook.hookPath.path)))
        #expect(!(FileManager.default.fileExists(atPath: hook.backupPath.path)))
        #expect(!(FileManager.default.fileExists(atPath: hook.sessionsDir.path)))
    }

    @Test func uninstallRemovesTheKeyWhenThereWasNoneAndLeavesAChangedEntryAlone() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try "{\"model\":\"x\"}".write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir)
        _ = try hook.install()
        try hook.uninstall(previousCommand: nil)
        let back = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? [String: Any])
        #expect(back["statusLine"] == nil)
        #expect(back["model"] as? String == "x")
        // the user replaced the entry after install: removing the hook leaves their entry in place
        _ = try hook.install()
        try "{\"statusLine\":{\"type\":\"command\",\"command\":\"mine\"}}".write(to: settings, atomically: true, encoding: .utf8)
        try hook.uninstall(previousCommand: nil)
        let kept = try #require(JSONSerialization.jsonObject(with: try Data(contentsOf: settings)) as? [String: Any])
        #expect((kept["statusLine"] as? [String: Any])?["command"] as? String == "mine")
    }

    @Test func installRefusesASettingsFileThatIsNotAnObject() throws {
        let dir = try tempDir()
        let settings = dir.appendingPathComponent("settings.json")
        try "[1, 2".write(to: settings, atomically: true, encoding: .utf8)
        let hook = Hook(settingsURL: settings, dataDir: dir)
        #expect(throws: HookError.self) { try hook.install() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == "[1, 2")
    }

    @Test func weekRecords() {
        var w = WeekRecords()
        let reset = Date(timeIntervalSince1970: 1792339200)
        w.apply(LimitWindow(key: "seven_day", usedPercentage: 61, resetsAt: reset), at: Date(timeIntervalSince1970: 1791900000))
        w.apply(LimitWindow(key: "seven_day", usedPercentage: 100, resetsAt: reset), at: Date(timeIntervalSince1970: 1791950000))
        w.apply(LimitWindow(key: "seven_day", usedPercentage: 100, resetsAt: reset), at: Date(timeIntervalSince1970: 1791960000))
        #expect(w.records.count == 1)
        #expect(w.records[0].hitAt == Date(timeIntervalSince1970: 1791950000))
        for k in 1...5 { w.apply(LimitWindow(key: "seven_day", usedPercentage: 50, resetsAt: reset.addingTimeInterval(Double(k) * 604800)), at: reset) }
        #expect(w.records.count == 4)
    }
}
