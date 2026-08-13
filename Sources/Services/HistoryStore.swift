import Foundation

/// Local session history: one JSON file per day under ~/.sessionhawk/history/
/// (2026-08-13.json), each an array of HistoryRecord. Plain JSON so users can
/// read their own data with jq — consistent with the "your data stays local
/// and inspectable" stance. Not thread-safe by design: all callers go through
/// the main actor (SessionManager timer + app startup).
public final class HistoryStore {
    public let directory: URL
    public static let retentionDays = 90

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".sessionhawk/history")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Local-calendar day key ("2026-08-13") — history is a human-facing
    /// "what did I do today" feature, so local days beat UTC days.
    public static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func fileURL(day: String) -> URL {
        directory.appendingPathComponent("\(day).json")
    }

    public func records(day: String) -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: fileURL(day: day)),
              let records = try? decoder.decode([HistoryRecord].self, from: data) else { return [] }
        return records
    }

    /// Merge records into their day files (day = session's firstSeen), keyed
    /// by session id — snapshots of a live session overwrite its previous
    /// snapshot instead of duplicating it.
    public func upsert(_ incoming: [HistoryRecord]) {
        let byDay = Dictionary(grouping: incoming) { Self.dayKey($0.firstSeen) }
        for (day, dayRecords) in byDay {
            var existing = records(day: day)
            for record in dayRecords {
                if let i = existing.firstIndex(where: { $0.id == record.id }) {
                    existing[i] = record
                } else {
                    existing.append(record)
                }
            }
            existing.sort { $0.firstSeen > $1.firstSeen }
            if let data = try? encoder.encode(existing) {
                try? data.write(to: fileURL(day: day), options: .atomic)
            }
        }
    }

    /// Day keys with data, newest first.
    public func days(limit: Int = 30) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted(by: >)
            .prefix(limit)
            .map { $0 }
    }

    /// Delete day files older than the retention window. Filename-based, so a
    /// stray non-date file is never touched.
    public func prune(keepDays: Int = HistoryStore.retentionDays, now: Date = Date()) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepDays, to: now) else { return }
        let cutoff = Self.dayKey(cutoffDate)
        for day in days(limit: .max) where day < cutoff && day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            try? FileManager.default.removeItem(at: fileURL(day: day))
        }
    }
}
