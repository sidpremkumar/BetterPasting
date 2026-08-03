import Foundation
import SQLite3

final class ClipboardStore: @unchecked Sendable {
    static let shared = ClipboardStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.betterpasting.store", qos: .userInitiated)

    private init() {
        openDatabase()
        enableWALMode()
        createTables()
        migrateSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("BetterPasting", isDirectory: true)

        // Create app support directory if needed
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        let dbPath = appDir.appendingPathComponent("clipboard.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[ClipboardStore] Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("[ClipboardStore] Database opened at: \(dbPath)")
        }
    }

    /// Enable Write-Ahead Logging for better concurrent read/write performance.
    private func enableWALMode() {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "unknown"
            print("[ClipboardStore] Failed to enable WAL mode: \(error)")
            sqlite3_free(errMsg)
        } else {
            print("[ClipboardStore] WAL mode enabled")
        }
    }

    private func createTables() {
        let sql = """
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                content_hash TEXT NOT NULL,
                content_type TEXT NOT NULL,
                text_content TEXT,
                image_path TEXT,
                file_paths TEXT,
                rtf_data BLOB,
                html_content TEXT,
                source_bundle_id TEXT,
                source_app_name TEXT,
                created_at REAL NOT NULL,
                is_pinned INTEGER DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_content_hash ON clipboard_items(content_hash);
            CREATE INDEX IF NOT EXISTS idx_is_pinned ON clipboard_items(is_pinned DESC, created_at DESC);

            CREATE TABLE IF NOT EXISTS link_previews (
                url TEXT PRIMARY KEY,
                title TEXT,
                summary TEXT,
                site_name TEXT,
                image_path TEXT,
                favicon_path TEXT,
                fetched_at REAL NOT NULL,
                did_fail INTEGER DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_preview_fetched_at ON link_previews(fetched_at);
            """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "unknown"
            print("[ClipboardStore] Failed to create tables: \(error)")
            sqlite3_free(errMsg)
        } else {
            print("[ClipboardStore] Tables created/verified")
        }
    }

    /// Columns added after a table shipped. ALTER TABLE fails harmlessly when the
    /// column is already there, which is how we detect "already migrated".
    private func migrateSchema() {
        let statements = [
            "ALTER TABLE link_previews ADD COLUMN image_url TEXT"
        ]

        for sql in statements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - CRUD Operations

    func insert(_ item: ClipboardItem) {
        queue.async { [weak self] in
            self?.insertSync(item)
        }
    }

    private func insertSync(_ item: ClipboardItem) {
        // Check for duplicate content hash (skip if already exists)
        if existsWithHash(item.contentHash) {
            // Move existing item to front by updating timestamp and source app info
            updateExistingItem(for: item.contentHash, sourceApp: item)
            print("[ClipboardStore] Duplicate detected, updated timestamp and source app")
            return
        }

        let sql = """
            INSERT INTO clipboard_items
            (id, content_hash, content_type, text_content, image_path, file_paths, rtf_data, html_content, source_bundle_id, source_app_name, created_at, is_pinned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[ClipboardStore] Failed to prepare insert: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, item.contentType.rawValue, -1, SQLITE_TRANSIENT)

        if let text = item.textContent {
            sqlite3_bind_text(stmt, 4, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }

        if let path = item.imagePath {
            sqlite3_bind_text(stmt, 5, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }

        if let paths = item.filePaths {
            let json = try? JSONEncoder().encode(paths)
            if let json = json {
                sqlite3_bind_text(stmt, 6, String(data: json, encoding: .utf8), -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if let rtf = item.rtfData {
            _ = rtf.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 7, ptr.baseAddress, Int32(rtf.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        if let html = item.htmlContent {
            sqlite3_bind_text(stmt, 8, html, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }

        if let bundleID = item.sourceBundleID {
            sqlite3_bind_text(stmt, 9, bundleID, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        if let appName = item.sourceAppName {
            sqlite3_bind_text(stmt, 10, appName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        sqlite3_bind_double(stmt, 11, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 12, item.isPinned ? 1 : 0)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[ClipboardStore] Failed to insert: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("[ClipboardStore] Inserted item: \(item.id)")
        }
    }

    private func existsWithHash(_ hash: String) -> Bool {
        let sql = "SELECT 1 FROM clipboard_items WHERE content_hash = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Update timestamp and source app info for a duplicate item to keep all three layers consistent
    private func updateExistingItem(for hash: String, sourceApp item: ClipboardItem) {
        let sql = """
            UPDATE clipboard_items
            SET created_at = ?, source_bundle_id = ?, source_app_name = ?
            WHERE content_hash = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)

        if let bundleID = item.sourceBundleID {
            sqlite3_bind_text(stmt, 2, bundleID, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }

        if let appName = item.sourceAppName {
            sqlite3_bind_text(stmt, 3, appName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }

        sqlite3_bind_text(stmt, 4, hash, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func fetchRecentItems(limit: Int = 500) -> [ClipboardItem] {
        var items: [ClipboardItem] = []

        queue.sync {
            let sql = """
                SELECT id, content_hash, content_type, text_content, image_path, file_paths,
                       rtf_data, html_content, source_bundle_id, source_app_name, created_at, is_pinned
                FROM clipboard_items
                ORDER BY is_pinned DESC, created_at DESC
                LIMIT ?
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("[ClipboardStore] Failed to prepare fetch: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = parseRow(stmt) {
                    items.append(item)
                }
            }
        }

        return items
    }

    private func parseRow(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idStr),
              let hash = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
              let typeStr = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
              let contentType = ContentType(rawValue: typeStr) else {
            return nil
        }

        let textContent = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let imagePath = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

        var filePaths: [String]?
        if let pathsStr = sqlite3_column_text(stmt, 5).map({ String(cString: $0) }),
           let data = pathsStr.data(using: .utf8) {
            filePaths = try? JSONDecoder().decode([String].self, from: data)
        }

        var rtfData: Data?
        if let blob = sqlite3_column_blob(stmt, 6) {
            let length = sqlite3_column_bytes(stmt, 6)
            rtfData = Data(bytes: blob, count: Int(length))
        }

        let htmlContent = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
        let sourceBundleID = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let sourceAppName = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
        let isPinned = sqlite3_column_int(stmt, 11) == 1

        return ClipboardItem(
            id: id,
            contentHash: hash,
            contentType: contentType,
            textContent: textContent,
            imagePath: imagePath,
            filePaths: filePaths,
            rtfData: rtfData,
            htmlContent: htmlContent,
            sourceBundleID: sourceBundleID,
            sourceAppName: sourceAppName,
            createdAt: createdAt,
            isPinned: isPinned
        )
    }

    /// Delete all unpinned items from the database. Used by "Clear History".
    func deleteUnpinned() {
        queue.sync {
            let sql = "DELETE FROM clipboard_items WHERE is_pinned = 0"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("[ClipboardStore] Failed to prepare deleteUnpinned: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_DONE {
                let count = sqlite3_changes(db)
                print("[ClipboardStore] Deleted \(count) unpinned items")
            } else {
                print("[ClipboardStore] Failed to deleteUnpinned: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    func delete(id: UUID) {
        queue.async { [weak self] in
            let sql = "DELETE FROM clipboard_items WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self?.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    func togglePinned(id: UUID, isPinned: Bool) {
        queue.async { [weak self] in
            let sql = "UPDATE clipboard_items SET is_pinned = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self?.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// Bubble up an item to the top by updating its timestamp (preserves source app info)
    func bubbleUp(id: UUID) {
        queue.async { [weak self] in
            let sql = "UPDATE clipboard_items SET created_at = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self?.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            print("[ClipboardStore] Bubbled up item: \(id)")
        }
    }

    // MARK: - Link Previews

    func fetchLinkPreview(url: String) -> LinkPreview? {
        var preview: LinkPreview?

        queue.sync {
            let sql = """
                SELECT url, title, summary, site_name, image_path, favicon_path, fetched_at, did_fail, image_url
                FROM link_previews
                WHERE url = ?
                LIMIT 1
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let urlStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { return }

            preview = LinkPreview(
                url: urlStr,
                title: sqlite3_column_text(stmt, 1).map { String(cString: $0) },
                summary: sqlite3_column_text(stmt, 2).map { String(cString: $0) },
                siteName: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                imageURL: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
                imageFilename: sqlite3_column_text(stmt, 4).map { String(cString: $0) },
                faviconFilename: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
                fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                didFail: sqlite3_column_int(stmt, 7) == 1
            )
        }

        return preview
    }

    func saveLinkPreview(_ preview: LinkPreview) {
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO link_previews
                (url, title, summary, site_name, image_path, favicon_path, fetched_at, did_fail, image_url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("[ClipboardStore] Failed to prepare saveLinkPreview: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, preview.url, -1, SQLITE_TRANSIENT)
            bindOptionalText(stmt, index: 2, value: preview.title)
            bindOptionalText(stmt, index: 3, value: preview.summary)
            bindOptionalText(stmt, index: 4, value: preview.siteName)
            bindOptionalText(stmt, index: 5, value: preview.imageFilename)
            bindOptionalText(stmt, index: 6, value: preview.faviconFilename)
            sqlite3_bind_double(stmt, 7, preview.fetchedAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 8, preview.didFail ? 1 : 0)
            bindOptionalText(stmt, index: 9, value: preview.imageURL)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[ClipboardStore] Failed to save link preview: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    /// Delete cached previews last fetched before the cutoff. Returns the number of deleted rows.
    func deleteLinkPreviewsOlderThan(_ cutoffDate: Date) -> Int {
        var deleted = 0
        queue.sync {
            let sql = "DELETE FROM link_previews WHERE fetched_at < ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, cutoffDate.timeIntervalSince1970)
            if sqlite3_step(stmt) == SQLITE_DONE {
                deleted = Int(sqlite3_changes(db))
            }
        }
        return deleted
    }

    /// Fetch all preview image and favicon filenames referenced by the database.
    func fetchAllLinkPreviewImagePaths() -> Set<String> {
        var paths = Set<String>()
        queue.sync {
            let sql = """
                SELECT image_path, favicon_path FROM link_previews
                WHERE image_path IS NOT NULL OR favicon_path IS NOT NULL
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                for column in Int32(0)...Int32(1) {
                    if let cStr = sqlite3_column_text(stmt, column) {
                        paths.insert(String(cString: cStr))
                    }
                }
            }
        }
        return paths
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    // MARK: - Cleanup Operations (used by CleanupManager)

    /// Delete unpinned items older than the cutoff date. Returns the number of deleted rows.
    func deleteOlderThan(_ cutoffDate: Date) -> Int {
        var deleted = 0
        queue.sync {
            let sql = "DELETE FROM clipboard_items WHERE created_at < ? AND is_pinned = 0"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, cutoffDate.timeIntervalSince1970)
            if sqlite3_step(stmt) == SQLITE_DONE {
                deleted = Int(sqlite3_changes(db))
            }
        }
        return deleted
    }

    /// Delete the oldest unpinned items that exceed `maxCount`. Returns the number of deleted rows.
    func deleteExcess(maxCount: Int) -> Int {
        var deleted = 0
        queue.sync {
            var currentCount = 0
            let countSql = "SELECT COUNT(*) FROM clipboard_items"
            var countStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
                if sqlite3_step(countStmt) == SQLITE_ROW {
                    currentCount = Int(sqlite3_column_int(countStmt, 0))
                }
                sqlite3_finalize(countStmt)
            }

            guard currentCount > maxCount else { return }

            let toDelete = currentCount - maxCount
            let sql = """
                DELETE FROM clipboard_items
                WHERE id IN (
                    SELECT id FROM clipboard_items
                    WHERE is_pinned = 0
                    ORDER BY created_at ASC
                    LIMIT ?
                )
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(toDelete))
            if sqlite3_step(stmt) == SQLITE_DONE {
                deleted = Int(sqlite3_changes(db))
            }
        }
        return deleted
    }

    /// Fetch all image paths currently stored in the database.
    func fetchAllImagePaths() -> Set<String> {
        var paths = Set<String>()
        queue.sync {
            let sql = "SELECT image_path FROM clipboard_items WHERE image_path IS NOT NULL"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    paths.insert(String(cString: cStr))
                }
            }
        }
        return paths
    }

    /// Run VACUUM to reclaim disk space.
    func vacuum() {
        queue.sync {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, "VACUUM", nil, nil, &errMsg) != SQLITE_OK {
                sqlite3_free(errMsg)
            }
        }
    }

    func itemCount() -> Int {
        var count = 0
        queue.sync {
            let sql = "SELECT COUNT(*) FROM clipboard_items"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        return count
    }
}

// MARK: - SQLite Constants

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
