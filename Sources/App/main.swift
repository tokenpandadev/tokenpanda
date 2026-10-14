// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import Text
import UI
import Transcripts
import MacStats

// Entry point of tokenpanda. Debug builds also take three flags that print or render and exit:
//   tokenpanda --snapshot <dir>         every tab and state of the sample data to PNG through the view's bitmap
//   tokenpanda --read-transcripts       one full pass over the transcripts: counts and seconds
//   tokenpanda --sample-mac <rounds>    the Mac sampler alone at 2 s, its own CPU time
// Release builds contain none of them.

#if DEBUG
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        var written: [String] = []
        for (name, input) in Fixtures.all() {
            let url = dir.appendingPathComponent(name + ".png")
            do { try SnapshotWriter.writeScreen(ScreenBuilder.screen(input), to: url); written.append(name) } catch { print("failed \(name): \(error)") }
        }
        let items: [(String, ItemState)] = [
            ("closed", ScreenBuilder.item(Fixtures.input(weekly: 61))),
            ("item-ahead", ScreenBuilder.item(Fixtures.input(weekly: 45))),
            ("item-stale", ScreenBuilder.item(Fixtures.input(weekly: 61, stale: true))),
            ("item-warning", ScreenBuilder.item(Fixtures.input(weekly: 61, warn: true))),
            ("item-nofeed", ScreenBuilder.item(Fixtures.input(feedState: .init()))),
        ]
        for (name, st) in items {
            do { try SnapshotWriter.writeItem(st, to: dir.appendingPathComponent(name + ".png")); written.append(name) } catch { print("failed \(name): \(error)") }
        }
        print("wrote \(written.count) PNGs to \(dir.path)")
    }
    exit(0)
}

if args.contains("--read-transcripts") {
    // one full pass over the transcripts, counts and time, then exit (no UI)
    let t0 = Date()
    let store = TranscriptStore(roots: TranscriptLocator.roots())
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let r = await store.refresh()
        let s = Aggregator.summarize(r.records)
        print("files \(r.fileCount) records \(r.records.count) tokens7d \(s.tokens7d) tokens30d \(s.tokens30d) error \(r.error ?? "none") in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        sem.signal()
    }
    sem.wait()
    exit(0)
}

if let i = args.firstIndex(of: "--sample-mac"), i + 1 < args.count, let rounds = Int(args[i + 1]) {
    // the Mac sampler alone, every 2 s, its own CPU time by getrusage, then exit
    let selfCPU: @Sendable () -> Double = { var ru = rusage(); getrusage(RUSAGE_SELF, &ru); return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6 }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let sampler = MacSampler()
        let wall0 = Date(), cpu0 = selfCPU()
        for r in 0..<rounds {
            let t = Date()
            let s = await sampler.sample(full: true)
            let took = Date().timeIntervalSince(t)
            if r == 0 || r == rounds - 1 { print("round \(r): cpu \(Int(s.cpuBusy))% gpu \(s.gpuUtilisation ?? -1) procs \(s.processes.count) total \(Int(s.processTotalCPU)) took \(String(format: "%.1f", took * 1000)) ms") }
            try? await Task.sleep(for: .seconds(max(0, 2 - took)))
        }
        let wall = Date().timeIntervalSince(wall0), cpu = selfCPU() - cpu0
        print(String(format: "sampling every 2 s for %.1f s: process CPU time %.3f s = %.2f%% of one core", wall, cpu, 100 * cpu / wall))
        sem.signal()
    }
    sem.wait()
    exit(0)
}
#endif

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.delegate = controller
app.run()
