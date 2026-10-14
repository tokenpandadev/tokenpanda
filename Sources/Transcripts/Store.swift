// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// Reads transcripts incrementally: every file remembers its byte offset and the message ids it has seen.
/// A file that shrank is read again from the start. Nothing is ever loaded whole.
public actor TranscriptStore {
    struct FileState {
        var offset: UInt64 = 0
        var ids: Set<String> = []
        var records: [UsageRecord] = []
    }

    public let roots: [URL]
    var files: [URL: FileState] = [:]
    public private(set) var lastError: String?
    public private(set) var fileCount = 0
    public private(set) var version = 0      // moves when a record was added or a file was read again

    public init(roots: [URL]) { self.roots = roots }

    public struct Result: Sendable {
        public var records: [UsageRecord]
        public var fileCount: Int
        public var rootsExist: Bool
        public var error: String?
        public var version: Int
    }

    var lastReportedVersion = -1

    /// Enumerates the files and reads what is new. Returns every record kept; with onlyIfChanged the records
    /// come back empty when nothing moved since the last call, so the caller keeps its aggregate without a copy.
    public func refresh(now: Date = Date(), chunk: Int = 1 << 20, onlyIfChanged: Bool = false) -> Result {
        let fm = FileManager.default
        let rootsExist = roots.contains { fm.fileExists(atPath: $0.path) }
        let found = TranscriptLocator.files(under: roots, now: now)
        let present = Set(found.map(\.url))
        for url in files.keys where !present.contains(url) { files.removeValue(forKey: url); version += 1 }
        var error: String? = nil   // this pass only: a later pass without an error clears it
        for f in found {
            var st = files[f.url] ?? FileState()
            if f.size < st.offset { st = FileState(); version += 1 }   // truncated or rewritten: start over
            if f.size > st.offset {
                do { try read(f, into: &st, chunk: chunk) } catch let e { error = e.localizedDescription }
            }
            files[f.url] = st
        }
        lastError = error
        fileCount = found.count
        let unchanged = onlyIfChanged && version == lastReportedVersion
        lastReportedVersion = version
        let all = unchanged ? [] : files.values.flatMap(\.records)
        return Result(records: all, fileCount: found.count, rootsExist: rootsExist, error: error, version: version)
    }

    func read(_ f: TranscriptFile, into st: inout FileState, chunk: Int) throws {
        // POSIX read into one buffer: no Foundation file object holds the file's pages across the pass
        let fd = open(f.url.path, O_RDONLY)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
        defer { close(fd) }
        guard lseek(fd, off_t(st.offset), SEEK_SET) >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var buffer: [UInt8] = []
        buffer.reserveCapacity(chunk * 2)
        var piece = [UInt8](repeating: 0, count: chunk)
        while true {
            let n = piece.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, chunk) }
            if n < 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
            if n == 0 { break }
            buffer.append(contentsOf: piece[0..<n])
            var start = 0
            buffer.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                while start < ptr.count, let hit = memchr(base + start, 0x0A, ptr.count - start) {
                    let nl = UnsafePointer<UInt8>(hit.assumingMemoryBound(to: UInt8.self)) - base
                    consume(UnsafeBufferPointer(rebasing: ptr[start..<nl]), f, &st)
                    start = nl + 1
                }
            }
            st.offset += UInt64(start)
            buffer.removeFirst(start)
        }
        // whatever is left has no newline yet; the offset stays before it and the line is read whole next time
    }

    static let marker = Array("\"type\":\"assistant\"".utf8)
    static let markerSpaced = Array("\"type\": \"assistant\"".utf8)

    /// A cheap scan for the assistant marker before any copy or decode.
    static func looksLikeAssistant(_ line: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = line.baseAddress, line.count > marker.count else { return false }
        return memmem(base, line.count, marker, marker.count) != nil || memmem(base, line.count, markerSpaced, markerSpaced.count) != nil
    }

    func consume(_ line: UnsafeBufferPointer<UInt8>, _ f: TranscriptFile, _ st: inout FileState) {
        guard !line.isEmpty, Self.looksLikeAssistant(line) else { return }
        consume(Data(buffer: line), f, &st)
    }

    func consume(_ line: Data, _ f: TranscriptFile, _ st: inout FileState) {
        guard !line.isEmpty, TranscriptParser.looksLikeAssistant(line) else { return }
        guard let p = TranscriptParser.parse(line: line, file: f) else { return }
        // one assistant line per content block, same id and same usage: keep the first, skip the repeats
        guard !st.ids.contains(p.messageId) else { return }
        st.ids.insert(p.messageId)
        st.records.append(p.record)
        version += 1
    }
}
