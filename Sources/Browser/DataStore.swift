import Foundation
import SQLite3

struct HistoryEntry: Equatable {
    var url: String
    var title: String
    var visitCount: Int
}

// One SQLite file holds history and the session blob.
// All access is serialized on an internal queue; callers may use any thread.
final class DataStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "browser.datastore")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            if let handle { sqlite3_close(handle) }
            throw DataStoreError.open(message)
        }
        db = handle
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
        try exec("PRAGMA busy_timeout=3000")
        try exec("PRAGMA synchronous=NORMAL")
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    enum DataStoreError: Error {
        case open(String)
        case exec(String)
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DataStoreError.exec(message)
        }
    }

    private func migrate() throws {
        let version = scalarInt("PRAGMA user_version") ?? 0
        if version < 1 {
            try exec("""
            CREATE TABLE IF NOT EXISTS urls (
                id INTEGER PRIMARY KEY,
                url TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL DEFAULT '',
                visit_count INTEGER NOT NULL DEFAULT 0,
                last_visit_at INTEGER NOT NULL DEFAULT 0,
                frecency REAL NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS urls_frecency ON urls(frecency DESC);
            CREATE TABLE IF NOT EXISTS visits (
                id INTEGER PRIMARY KEY,
                url_id INTEGER NOT NULL REFERENCES urls(id) ON DELETE CASCADE,
                visited_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS visits_url ON visits(url_id);
            CREATE TABLE IF NOT EXISTS session (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                schema_version INTEGER NOT NULL,
                blob TEXT NOT NULL
            );
            PRAGMA user_version = 1;
            """)
        }
        if version < 2 {
            try exec("""
            CREATE TABLE IF NOT EXISTS site_zoom (
                host TEXT PRIMARY KEY,
                zoom REAL NOT NULL
            );
            PRAGMA user_version = 2;
            """)
        }
    }

    private func scalarInt(_ sql: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: History

    func recordVisit(url: String, title: String, at time: Date = Date()) {
        let ts = Int64(time.timeIntervalSince1970)
        queue.sync {
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO urls (url, title, visit_count, last_visit_at, frecency)
            VALUES (?1, ?2, 1, ?3, 100)
            ON CONFLICT(url) DO UPDATE SET
                title = CASE WHEN excluded.title != '' THEN excluded.title ELSE urls.title END,
                visit_count = urls.visit_count + 1,
                last_visit_at = excluded.last_visit_at,
                frecency = urls.frecency * 0.9 + 100
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, url, -1, DataStore.transient)
            sqlite3_bind_text(stmt, 2, title, -1, DataStore.transient)
            sqlite3_bind_int64(stmt, 3, ts)
            sqlite3_step(stmt)

            var visit: OpaquePointer?
            let visitSQL = "INSERT INTO visits (url_id, visited_at) SELECT id, ?2 FROM urls WHERE url = ?1"
            guard sqlite3_prepare_v2(db, visitSQL, -1, &visit, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(visit) }
            sqlite3_bind_text(visit, 1, url, -1, DataStore.transient)
            sqlite3_bind_int64(visit, 2, ts)
            sqlite3_step(visit)
        }
    }

    func updateTitle(url: String, title: String) {
        guard !title.isEmpty else { return }
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE urls SET title = ?2 WHERE url = ?1", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, url, -1, DataStore.transient)
            sqlite3_bind_text(stmt, 2, title, -1, DataStore.transient)
            sqlite3_step(stmt)
        }
    }

    func suggest(_ query: String, limit: Int = 10) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        return queue.sync {
            var stmt: OpaquePointer?
            let sql = """
            SELECT url, title, visit_count FROM urls
            WHERE url LIKE ?1 ESCAPE '\\' OR title LIKE ?1 ESCAPE '\\'
            ORDER BY frecency DESC LIMIT ?2
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pattern, -1, DataStore.transient)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            var out: [HistoryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let url = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let count = Int(sqlite3_column_int64(stmt, 2))
                out.append(HistoryEntry(url: url, title: title, visitCount: count))
            }
            return out
        }
    }

    // MARK: Per-site zoom

    func setZoom(_ zoom: Double, host: String) {
        guard !host.isEmpty else { return }
        queue.sync {
            var stmt: OpaquePointer?
            if abs(zoom - 1.0) < 0.001 {
                guard sqlite3_prepare_v2(db, "DELETE FROM site_zoom WHERE host = ?1", -1, &stmt, nil) == SQLITE_OK else { return }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, host, -1, DataStore.transient)
                sqlite3_step(stmt)
                return
            }
            let sql = "INSERT INTO site_zoom (host, zoom) VALUES (?1, ?2) ON CONFLICT(host) DO UPDATE SET zoom = excluded.zoom"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, host, -1, DataStore.transient)
            sqlite3_bind_double(stmt, 2, zoom)
            sqlite3_step(stmt)
        }
    }

    func zoom(forHost host: String) -> Double? {
        guard !host.isEmpty else { return nil }
        return queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT zoom FROM site_zoom WHERE host = ?1", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, host, -1, DataStore.transient)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return sqlite3_column_double(stmt, 0)
        }
    }

    // MARK: Session

    func saveSession(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        queue.sync {
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO session (id, schema_version, blob) VALUES (1, ?1, ?2)
            ON CONFLICT(id) DO UPDATE SET schema_version = excluded.schema_version, blob = excluded.blob
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(snapshot.schemaVersion))
            sqlite3_bind_text(stmt, 2, json, -1, DataStore.transient)
            sqlite3_step(stmt)
        }
    }

    func loadSession() -> SessionSnapshot? {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT blob FROM session WHERE id = 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let text = sqlite3_column_text(stmt, 0) else { return nil }
            let json = String(cString: text)
            return try? JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        }
    }
}
