import Foundation
import SQLite3

final class CleanupManager: @unchecked Sendable {
    static let shared = CleanupManager()

    private let store: ClipboardStore
    private let imageCache: ImageCache
    private var cleanupTimer: Timer?

    private init() {
        self.store = ClipboardStore.shared
        self.imageCache = ImageCache.shared
    }

    func startPeriodicCleanup() {
        // Run cleanup on launch
        runCleanup()

        // Schedule cleanup every 6 hours
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runCleanup()
        }
    }

    func stopPeriodicCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func runCleanup() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let prefs = UserPreferences.load()
            let startTime = CFAbsoluteTimeGetCurrent()

            let deletedByAge = self.cleanupOldItems(maxAgeDays: prefs.maxAgeDays)
            let deletedByCount = self.cleanupExcessItems(maxCount: prefs.maxItemCount)
            self.cleanupOrphanedImages()
            self.vacuumDatabase()

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("[CleanupManager] Cleanup completed in \(Int(elapsed))ms - deleted \(deletedByAge) by age, \(deletedByCount) by count")
        }
    }

    /// Delete items older than maxAgeDays (except pinned)
    private func cleanupOldItems(maxAgeDays: Int) -> Int {
        let cutoffDate = Date().addingTimeInterval(-Double(maxAgeDays) * 24 * 60 * 60)
        let cutoff = cutoffDate.timeIntervalSince1970

        var deletedCount = 0

        // Get items to delete
        let sql = """
            DELETE FROM clipboard_items
            WHERE created_at < ? AND is_pinned = 0
            """

        let db = openDatabase()
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        if sqlite3_step(stmt) == SQLITE_DONE {
            deletedCount = Int(sqlite3_changes(db))
        }

        return deletedCount
    }

    /// Keep only maxCount most recent items (except pinned)
    private func cleanupExcessItems(maxCount: Int) -> Int {
        let db = openDatabase()
        defer { sqlite3_close(db) }

        // Count current items
        var currentCount = 0
        let countSql = "SELECT COUNT(*) FROM clipboard_items"
        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                currentCount = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }

        guard currentCount > maxCount else { return 0 }

        // Delete oldest items beyond limit (except pinned)
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
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(toDelete))

        if sqlite3_step(stmt) == SQLITE_DONE {
            return Int(sqlite3_changes(db))
        }

        return 0
    }

    /// Delete image files with no corresponding database entry
    private func cleanupOrphanedImages() {
        let db = openDatabase()
        defer { sqlite3_close(db) }

        // Get all image paths from database
        var dbPaths = Set<String>()
        let sql = "SELECT image_path FROM clipboard_items WHERE image_path IS NOT NULL"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let path = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) {
                    dbPaths.insert(path)
                }
            }
            sqlite3_finalize(stmt)
        }

        // Get all image files
        let filePaths = Set(imageCache.getAllImageFiles())

        // Delete orphaned files
        let orphaned = filePaths.subtracting(dbPaths)
        for path in orphaned {
            imageCache.deleteImage(path: path)
        }

        if !orphaned.isEmpty {
            print("[CleanupManager] Deleted \(orphaned.count) orphaned images")
        }
    }

    private func vacuumDatabase() {
        let db = openDatabase()
        defer { sqlite3_close(db) }

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "VACUUM", nil, nil, &errMsg) != SQLITE_OK {
            sqlite3_free(errMsg)
        }
    }

    private func openDatabase() -> OpaquePointer? {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("BetterPasting/clipboard.db").path

        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        return db
    }
}
