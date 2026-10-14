import Foundation
import SQLite3
import os

struct FileStamp {
    var fileSize: Int64
    var mtime: TimeInterval
    var artworkPath: String
}

/// Serial SQLite index. The UI never scans files to draw the first screen.
final class LibraryStore {
    private let queue = DispatchQueue(label: "flacplayer.db", qos: .userInitiated)
    private var db: OpaquePointer?
    private let log = Logger(subsystem: "local.flacplayer", category: "db")
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    var isOpen: Bool { db != nil }

    init() {
        queue.sync {
            openLocked()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func stamps() -> [String: FileStamp] {
        queue.sync { stampsLocked() }
    }

    func upsert(_ record: StoredTrack) {
        queue.sync { upsertLocked(record) }
    }

    func upsertMany(_ records: [StoredTrack]) {
        guard !records.isEmpty else { return }
        queue.sync {
            exec("BEGIN IMMEDIATE")
            for record in records {
                upsertLocked(record)
            }
            exec("COMMIT")
        }
    }

    func updateDuration(path: String, duration: TimeInterval) {
        queue.sync {
            let sql = "UPDATE tracks SET duration = ? WHERE path = ?"
            var stmt: OpaquePointer?
            guard prepare(sql, &stmt), let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, duration)
            bindText(stmt, 2, path)
            sqlite3_step(stmt)
        }
    }

    func prune(keeping paths: Set<String>) {
        queue.sync {
            let existing = allPathsLocked()
            exec("BEGIN IMMEDIATE")
            for path in existing where !paths.contains(path) {
                deleteLocked(path)
            }
            exec("COMMIT")
        }
    }

    func fetchAlbums() -> [Album] {
        queue.sync { fetchAlbumsLocked() }
    }

    private func openLocked() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            log.error("Unable to create Application Support: \(error.localizedDescription, privacy: .public)")
            return
        }
        let path = folder.appendingPathComponent("library.sqlite").path
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            log.error("Unable to open library index")
            db = nil
            return
        }
        sqlite3_busy_timeout(db, 2000)
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
        CREATE TABLE IF NOT EXISTS tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album_artist TEXT NOT NULL,
            album TEXT NOT NULL,
            year INTEGER,
            track_number INTEGER NOT NULL DEFAULT 0,
            disc_number INTEGER NOT NULL DEFAULT 1,
            duration REAL NOT NULL DEFAULT 0,
            artwork_path TEXT NOT NULL DEFAULT '',
            file_size INTEGER NOT NULL DEFAULT 0,
            mtime REAL NOT NULL DEFAULT 0
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album_artist, album)")
    }

    private func stampsLocked() -> [String: FileStamp] {
        guard db != nil else { return [:] }
        let sql = "SELECT path, file_size, mtime, artwork_path FROM tracks"
        var stmt: OpaquePointer?
        guard prepare(sql, &stmt), let stmt else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var result: [String: FileStamp] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = columnText(stmt, 0)
            result[path] = FileStamp(
                fileSize: sqlite3_column_int64(stmt, 1),
                mtime: sqlite3_column_double(stmt, 2),
                artworkPath: columnText(stmt, 3)
            )
        }
        return result
    }

    private func upsertLocked(_ record: StoredTrack) {
        let sql = """
        INSERT INTO tracks (
            path, title, artist, album_artist, album, year, track_number, disc_number,
            duration, artwork_path, file_size, mtime
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            title = excluded.title,
            artist = excluded.artist,
            album_artist = excluded.album_artist,
            album = excluded.album,
            year = excluded.year,
            track_number = excluded.track_number,
            disc_number = excluded.disc_number,
            duration = excluded.duration,
            artwork_path = excluded.artwork_path,
            file_size = excluded.file_size,
            mtime = excluded.mtime
        """
        var stmt: OpaquePointer?
        guard prepare(sql, &stmt), let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, record.path)
        bindText(stmt, 2, record.title)
        bindText(stmt, 3, record.artist)
        bindText(stmt, 4, record.albumArtist)
        bindText(stmt, 5, record.album)
        if let year = record.year {
            sqlite3_bind_int(stmt, 6, Int32(year))
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_int(stmt, 7, Int32(record.trackNumber))
        sqlite3_bind_int(stmt, 8, Int32(record.discNumber))
        sqlite3_bind_double(stmt, 9, record.duration)
        bindText(stmt, 10, record.artworkPath)
        sqlite3_bind_int64(stmt, 11, record.fileSize)
        sqlite3_bind_double(stmt, 12, record.mtime)
        if sqlite3_step(stmt) != SQLITE_DONE {
            log.error("Upsert failed for \(record.path, privacy: .public)")
        }
    }

    private func deleteLocked(_ path: String) {
        var stmt: OpaquePointer?
        guard prepare("DELETE FROM tracks WHERE path = ?", &stmt), let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, path)
        sqlite3_step(stmt)
    }

    private func allPathsLocked() -> [String] {
        var stmt: OpaquePointer?
        guard prepare("SELECT path FROM tracks", &stmt), let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            paths.append(columnText(stmt, 0))
        }
        return paths
    }

    private func fetchAlbumsLocked() -> [Album] {
        guard db != nil else { return [] }
        let sql = """
        SELECT id, path, title, artist, album_artist, album, year, track_number, disc_number, duration, artwork_path
        FROM tracks
        ORDER BY album_artist COLLATE NOCASE, album COLLATE NOCASE, disc_number, track_number, title COLLATE NOCASE
        """
        var stmt: OpaquePointer?
        guard prepare(sql, &stmt), let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var albums: [Album] = []
        var currentKey: String?
        var bucket: [Track] = []

        func flush() {
            guard let first = bucket.first, let key = currentKey else { return }
            let year = bucket.compactMap(\.year).min()
            albums.append(Album(
                id: key,
                title: first.album,
                artist: first.albumArtist,
                year: year,
                tracks: bucket.sorted(by: trackOrder)
            ))
            bucket.removeAll(keepingCapacity: true)
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let track = Track(
                id: sqlite3_column_int64(stmt, 0),
                path: columnText(stmt, 1),
                title: columnText(stmt, 2),
                artist: columnText(stmt, 3),
                albumArtist: columnText(stmt, 4),
                album: columnText(stmt, 5),
                year: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6)),
                trackNumber: Int(sqlite3_column_int(stmt, 7)),
                discNumber: Int(sqlite3_column_int(stmt, 8)),
                duration: sqlite3_column_double(stmt, 9),
                artworkPath: {
                    let value = columnText(stmt, 10)
                    return value.isEmpty ? nil : value
                }()
            )
            let key = track.albumArtist.lowercased() + "\u{1f}" + track.album.lowercased()
            if currentKey != key {
                flush()
                currentKey = key
            }
            bucket.append(track)
        }
        flush()

        albums.sort { lhs, rhs in
            let artist = lhs.artist.localizedCaseInsensitiveCompare(rhs.artist)
            if artist != .orderedSame { return artist == .orderedAscending }
            let leftYear = lhs.year ?? Int.max
            let rightYear = rhs.year ?? Int.max
            if leftYear != rightYear { return leftYear < rightYear }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return albums
    }

    private func trackOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func prepare(_ sql: String, _ stmt: inout OpaquePointer?) -> Bool {
        guard let db else { return false }
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            return true
        }
        let message = String(cString: sqlite3_errmsg(db))
        log.error("SQL prepare failed: \(message, privacy: .public)")
        return false
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            log.error("SQL exec failed: \(message, privacy: .public)")
        }
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        _ = value.withCString { cString in
            sqlite3_bind_text(stmt, index, cString, -1, transient)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
}

struct StoredTrack {
    var path: String
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var year: Int?
    var trackNumber: Int
    var discNumber: Int
    var duration: TimeInterval
    var artworkPath: String
    var fileSize: Int64
    var mtime: TimeInterval
}
