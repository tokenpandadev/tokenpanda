import Foundation
import Prices

/// One assistant message, with only the fields the app keeps. The rest of the line is dropped at decode time.
public struct UsageRecord: Sendable, Equatable {
    public var timestamp: Date
    public var model: String
    public var project: String       // the display name: the working directory's last path segment
    public var session: String
    public var isAgent: Bool
    public var usage: Usage
    public init(timestamp: Date, model: String, project: String, session: String, isAgent: Bool, usage: Usage) {
        self.timestamp = timestamp; self.model = model; self.project = project; self.session = session; self.isAgent = isAgent; self.usage = usage
    }
}

struct RawLine: Decodable {
    var type: String?
    var timestamp: String?
    var isSidechain: Bool?
    var sessionId: String?
    var requestId: String?
    var cwd: String?
    var message: RawMessage?
}
struct RawMessage: Decodable {
    var id: String?
    var model: String?
    var usage: RawUsage?
}
struct RawUsage: Decodable {
    var input_tokens: Int?
    var output_tokens: Int?
    var cache_read_input_tokens: Int?
    var cache_creation_input_tokens: Int?
    var cache_creation: RawCacheCreation?
}
struct RawCacheCreation: Decodable {
    var ephemeral_5m_input_tokens: Int?
    var ephemeral_1h_input_tokens: Int?
}

public enum TranscriptParser {
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    public struct Parsed: Sendable, Equatable {
        public var messageId: String
        public var record: UsageRecord
    }

    /// Decodes one line. Returns nil for anything that is not an assistant line with a usage object,
    /// for a synthetic model, and for a line that cannot be read.
    public static func parse(line: Data, file: TranscriptFile) -> Parsed? {
        guard let raw = try? JSONDecoder().decode(RawLine.self, from: line) else { return nil }
        guard raw.type == "assistant", let m = raw.message, let id = m.id, let model = m.model, model != "<synthetic>",
              let u = m.usage, let ts = raw.timestamp else { return nil }
        guard let date = iso.date(from: ts) ?? isoPlain.date(from: ts) else { return nil }
        let project = raw.cwd.map { ($0 as NSString).lastPathComponent } ?? TranscriptLocator.projectName(fromFolder: file.projectFolder)
        let usage = Usage(input: u.input_tokens ?? 0, output: u.output_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0,
                          cacheWrite: u.cache_creation_input_tokens ?? 0,
                          cacheWrite5m: u.cache_creation?.ephemeral_5m_input_tokens, cacheWrite1h: u.cache_creation?.ephemeral_1h_input_tokens)
        let rec = UsageRecord(timestamp: date, model: model, project: project, session: raw.sessionId ?? file.sessionId,
                              isAgent: file.isAgent || (raw.isSidechain ?? false), usage: usage)
        return Parsed(messageId: id, record: rec)
    }

    /// A cheap test before decoding: only assistant lines are worth a decode.
    static let assistantMarker = Data("\"type\":\"assistant\"".utf8)
    static let assistantMarkerSpaced = Data("\"type\": \"assistant\"".utf8)
    public static func looksLikeAssistant(_ line: Data) -> Bool {
        line.range(of: assistantMarker) != nil || line.range(of: assistantMarkerSpaced) != nil
    }
}
