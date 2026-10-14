import SQLite3
import Foundation

public enum SQLiteVersion {
    public static let string = String(cString: sqlite3_libversion())
}
