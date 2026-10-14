// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Darwin
import IOKit
import IOKit.ps

// Every call is a public Mach, sysctl, IOKit or libproc call made in process. No tool is spawned, no root, no entitlement.
// Two readings depend on keys Apple does not document (GPU utilisation, battery health): shown when present, omitted when absent.

public struct ProcessSample: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double      // of one core, over the sampling interval
    public var footprint: UInt64       // bytes
    public init(pid: Int32, name: String, cpuPercent: Double, footprint: UInt64) { self.pid = pid; self.name = name; self.cpuPercent = cpuPercent; self.footprint = footprint }
}

public struct BatterySample: Sendable, Equatable {
    public var percent: Int
    public var charging: Bool
    public var charged: Bool
    public var onAC: Bool
    public var minutesToFull: Int?     // nil when unknown (65535 or 0 while not charging)
    public var minutesToEmpty: Int?
    public var adapterWatts: Int?
    public var watts: Double?          // voltage times amperage; negative when discharging
    public var cycles: Int?
    public var healthPercent: Int?     // nil on a Mac without the capacity keys
    public init(percent: Int, charging: Bool, charged: Bool, onAC: Bool, minutesToFull: Int?, minutesToEmpty: Int?, adapterWatts: Int?, watts: Double?, cycles: Int?, healthPercent: Int?) {
        self.percent = percent; self.charging = charging; self.charged = charged; self.onAC = onAC; self.minutesToFull = minutesToFull
        self.minutesToEmpty = minutesToEmpty; self.adapterWatts = adapterWatts; self.watts = watts; self.cycles = cycles; self.healthPercent = healthPercent
    }
}

public struct MacSample: Sendable, Equatable {
    public var cpuBusy: Double
    public var cpuUser: Double
    public var cpuSystem: Double
    public var cores: Int
    public var gpuUtilisation: Int?
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var pressureLevel: Int      // 1 normal, 2 warn, 4 critical
    public var swapUsed: UInt64
    public var battery: BatterySample?
    public var processes: [ProcessSample]   // the five busiest by CPU
    public var processTotalCPU: Double = 0  // every sampled process summed, in the same per core units: the CPU in use
    public var processError: String?
    public var hogPid: Int32?          // a process over 80% CPU in this sample
    public init(cpuBusy: Double, cpuUser: Double, cpuSystem: Double, cores: Int, gpuUtilisation: Int?, memoryUsed: UInt64, memoryTotal: UInt64,
                pressureLevel: Int, swapUsed: UInt64, battery: BatterySample?, processes: [ProcessSample], processError: String?, hogPid: Int32?) {
        self.cpuBusy = cpuBusy; self.cpuUser = cpuUser; self.cpuSystem = cpuSystem; self.cores = cores; self.gpuUtilisation = gpuUtilisation
        self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal; self.pressureLevel = pressureLevel; self.swapUsed = swapUsed
        self.battery = battery; self.processes = processes; self.processError = processError; self.hogPid = hogPid
    }

    public var pressureWord: String {
        switch pressureLevel { case 2: return "warn"; case 4: return "critical"; default: return "normal" }
    }
}

public actor MacSampler {
    public static let hogThreshold = 80.0
    var previousTicks: [UInt32]? = nil   // per core: user, system, idle, nice
    var previousProc: [Int32: (UInt64, Date)] = [:]
    var lastSampleAt: Date? = nil
    let cores: Int
    let ticksToNanos: Double   // rusage times are Mach absolute time ticks, not nanoseconds

    public init() {
        var n: Int32 = 0; var len = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &n, &len, nil, 0)
        cores = Int(max(n, 1))
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        ticksToNanos = tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }

    /// full: the whole table (popover open). Otherwise CPU, pressure and one libproc pass for the warning rule.
    public func sample(full: Bool, now: Date = Date()) -> MacSample {
        let cpu = sampleCPU()
        let (used, total, pressure, swap) = sampleMemory()
        let procs = sampleProcesses(now: now)
        var s = MacSample(cpuBusy: cpu.busy, cpuUser: cpu.user, cpuSystem: cpu.system, cores: cores, gpuUtilisation: nil,
                          memoryUsed: used, memoryTotal: total, pressureLevel: pressure, swapUsed: swap,
                          battery: nil, processes: procs.top, processError: procs.error, hogPid: procs.hog)
        s.processTotalCPU = procs.total
        if full {
            s.gpuUtilisation = sampleGPU()
            s.battery = sampleBattery()
        }
        lastSampleAt = now
        return s
    }

    // MARK: CPU, host_processor_info tick deltas

    func sampleCPU() -> (busy: Double, user: Double, system: Double) {
        var ncpu: natural_t = 0
        var info: processor_info_array_t? = nil
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count) == KERN_SUCCESS, let info else {
            return (0, 0, 0)
        }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let states = Int(CPU_STATE_MAX)
        var ticks: [UInt32] = []
        ticks.reserveCapacity(Int(ncpu) * states)
        for i in 0..<Int(ncpu) * states { ticks.append(UInt32(bitPattern: info[i])) }
        defer { previousTicks = ticks }
        guard let prev = previousTicks, prev.count == ticks.count else { return (0, 0, 0) }
        var user = 0.0, sys = 0.0, total = 0.0
        for c in 0..<Int(ncpu) {
            let base = c * states
            let du = Double(ticks[base + Int(CPU_STATE_USER)] &- prev[base + Int(CPU_STATE_USER)])
            let ds = Double(ticks[base + Int(CPU_STATE_SYSTEM)] &- prev[base + Int(CPU_STATE_SYSTEM)])
            let di = Double(ticks[base + Int(CPU_STATE_IDLE)] &- prev[base + Int(CPU_STATE_IDLE)])
            let dn = Double(ticks[base + Int(CPU_STATE_NICE)] &- prev[base + Int(CPU_STATE_NICE)])
            user += du + dn; sys += ds; total += du + ds + di + dn
        }
        guard total > 0 else { return (0, 0, 0) }
        return ((user + sys) / total * 100, user / total * 100, sys / total * 100)
    }

    // MARK: memory, host_statistics64, Activity Monitor style used

    func sampleMemory() -> (UInt64, UInt64, Int, UInt64) {
        var vm = vm_statistics64_data_t()
        var c = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c) }
        }
        var page: vm_size_t = 0
        host_page_size(mach_host_self(), &page)
        var memsize: UInt64 = 0; var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memsize, &len, nil, 0)
        var used: UInt64 = 0
        if kr == KERN_SUCCESS {
            let app = Int64(vm.internal_page_count) - Int64(vm.purgeable_count)
            let pages = max(app, 0) + Int64(vm.wire_count) + Int64(vm.compressor_page_count)
            used = UInt64(pages) * UInt64(page)
        }
        var lvl: Int32 = 1; var l1 = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &lvl, &l1, nil, 0)
        var sw = xsw_usage(); var l2 = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &sw, &l2, nil, 0)
        return (used, memsize, Int(lvl), sw.xsu_used)
    }

    // MARK: GPU, IOAccelerator PerformanceStatistics (undocumented key, best effort)

    func sampleGPU() -> Int? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var result: Int? = nil
        var e = IOIteratorNext(it)
        while e != 0 {
            var props: Unmanaged<CFMutableDictionary>? = nil
            if IORegistryEntryCreateCFProperties(e, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any], let ps = d["PerformanceStatistics"] as? [String: Any] {
                if let u = ps["Device Utilization %"] as? Int { result = u }
                else if let u = ps["GPU Activity(%)"] as? Int { result = u }
            }
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
        return result
    }

    // MARK: battery, IOPowerSources plus the AppleSmartBattery registry entry

    func sampleBattery() -> BatterySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var out: BatterySample? = nil
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType, let pct = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let state = d[kIOPSPowerSourceStateKey] as? String
            var b = BatterySample(percent: pct, charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                  charged: d[kIOPSIsChargedKey] as? Bool ?? false, onAC: state == kIOPSACPowerValue,
                                  minutesToFull: nil, minutesToEmpty: nil, adapterWatts: nil, watts: nil, cycles: nil, healthPercent: nil)
            if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0, t != 65535 { b.minutesToFull = t }
            if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0, t != 65535 { b.minutesToEmpty = t }
            out = b
        }
        guard var b = out else { return nil }
        if let ad = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any], let w = ad[kIOPSPowerAdapterWattsKey] as? Int {
            b.adapterWatts = w
        }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            var props: Unmanaged<CFMutableDictionary>? = nil
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS, let d = props?.takeRetainedValue() as? [String: Any] {
                b.cycles = d["CycleCount"] as? Int
                if let v = d["Voltage"] as? Int, let a = d["Amperage"] as? Int {
                    let amps = Int64(Int32(truncatingIfNeeded: a))   // the registry stores a signed value in an unsigned slot
                    b.watts = Double(v) / 1000 * Double(amps) / 1000
                }
                if let design = d["DesignCapacity"] as? Int, design > 0 {
                    if let nominal = d["NominalChargeCapacity"] as? Int { b.healthPercent = Int((Double(nominal) / Double(design) * 100).rounded()) }
                    else if let raw = d["AppleRawMaxCapacity"] as? Int { b.healthPercent = Int((Double(raw) / Double(design) * 100).rounded()) }
                }
            }
        }
        return b
    }

    // MARK: processes, libproc rusage deltas between two samples

    func sampleProcesses(now: Date) -> (top: [ProcessSample], error: String?, hog: Int32?, total: Double) {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return ([], "proc_listallpids returned nothing", nil, 0) }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return ([], "proc_listallpids failed", nil, 0) }
        var next: [Int32: (UInt64, Date)] = [:]
        var samples: [ProcessSample] = []
        var ok = 0
        var ri = rusage_info_v6()
        for i in 0..<Int(got) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let r = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard r == 0 else { continue }
            ok += 1
            let cpuTime = ri.ri_user_time &+ ri.ri_system_time
            next[pid] = (cpuTime, now)
            guard let (prevTime, prevAt) = previousProc[pid], cpuTime >= prevTime else { continue }
            let wall = now.timeIntervalSince(prevAt)
            guard wall > 0 else { continue }
            let pct = Double(cpuTime - prevTime) * ticksToNanos / 1e9 / wall * 100
            samples.append(ProcessSample(pid: pid, name: "", cpuPercent: pct, footprint: ri.ri_phys_footprint))
        }
        previousProc = next
        guard ok > 0 else { return ([], "proc_pid_rusage failed for every process", nil, 0) }
        samples.sort { $0.cpuPercent > $1.cpuPercent }
        let hog = samples.first.flatMap { $0.cpuPercent > MacSampler.hogThreshold ? $0.pid : nil }
        var top = Array(samples.prefix(5))
        for i in top.indices { top[i].name = Self.name(of: top[i].pid) }
        return (top, nil, hog, samples.reduce(0) { $0 + $1.cpuPercent })
    }

    static func name(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = proc_name(pid, &buf, UInt32(buf.count))
        if n > 0 { return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        return "pid \(pid)"
    }
}
