import Foundation
import SQLite3

struct SQLiteFTS5Unavailable: Error, CustomStringConvertible {
    var description: String { "Full-text search is unavailable in this macOS's SQLite" }
}

struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String

    var description: String { "SQLite (\(code)): \(message)" }
}

enum SQLiteValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

/// Owned by SearchIndex. All access is synchronous and serialized by that actor.
final class SQLiteDatabase {
    fileprivate let handle: OpaquePointer

    init(url: URL) throws {
        handle = try Self.open(url: url)
    }

    private static func open(url: URL) throws -> OpaquePointer {
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "No database handle"
            if let opened { sqlite3_close_v2(opened) }
            throw SQLiteError(code: result, message: message)
        }
        do {
            let timeoutResult = sqlite3_busy_timeout(opened, 2_000)
            guard timeoutResult == SQLITE_OK else {
                throw SQLiteError(code: timeoutResult, message: String(cString: sqlite3_errmsg(opened)))
            }
            let pragmaResult = sqlite3_exec(opened, "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;", nil, nil, nil)
            guard pragmaResult == SQLITE_OK else {
                throw SQLiteError(code: pragmaResult, message: String(cString: sqlite3_errmsg(opened)))
            }
            return opened
        } catch {
            sqlite3_close_v2(opened)
            throw error
        }
    }

    deinit { sqlite3_close_v2(handle) }

    static func probeFTS5() throws {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(":memory:", &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close_v2(database) }
            throw SQLiteError(code: openResult, message: "Could not open an in-memory SQLite database")
        }
        defer { sqlite3_close_v2(database) }
        let result = sqlite3_exec(
            database,
            "CREATE VIRTUAL TABLE temp.__fts5_probe USING fts5(content); DROP TABLE temp.__fts5_probe;",
            nil, nil, nil
        )
        guard result == SQLITE_OK else { throw SQLiteFTS5Unavailable() }
    }

    fileprivate func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    func exec(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard result == SQLITE_OK else {
            throw SQLiteError(
                code: result,
                message: message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            )
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(database: self, sql: sql)
    }

    func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try prepare(sql).run(values)
    }

    var lastInsertedID: Int64 { sqlite3_last_insert_rowid(handle) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }
}

final class SQLiteStatement {
    private let database: SQLiteDatabase
    private let handle: OpaquePointer

    fileprivate init(database: SQLiteDatabase, sql: String) throws {
        self.database = database
        var prepared: OpaquePointer?
        let result = sqlite3_prepare_v2(database.handle, sql, -1, &prepared, nil)
        guard result == SQLITE_OK, let prepared else {
            if let prepared { sqlite3_finalize(prepared) }
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(database.handle)))
        }
        handle = prepared
    }

    deinit { sqlite3_finalize(handle) }

    func bind(_ values: [SQLiteValue]) throws {
        try database.check(sqlite3_reset(handle))
        try database.check(sqlite3_clear_bindings(handle))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = text.withCString { sqlite3_bind_text64(handle, index, $0, UInt64(text.utf8.count), transient, UInt8(SQLITE_UTF8)) }
            case .int(let value): result = sqlite3_bind_int64(handle, index, value)
            case .double(let value): result = sqlite3_bind_double(handle, index, value)
            case .null: result = sqlite3_bind_null(handle, index)
            }
            try database.check(result)
        }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(database.handle)))
    }

    func run(_ values: [SQLiteValue] = []) throws {
        try bind(values)
        while try step() {}
    }

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }

    func text(_ column: Int32) -> String? {
        guard !isNull(column), let bytes = sqlite3_column_text(handle, column) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(handle, column))), as: UTF8.self)
    }
}
