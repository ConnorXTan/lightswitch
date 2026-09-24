import Foundation
import os

/// Unified logging, plus a stderr echo when the app runs in snapshot mode so
/// a terminal session can watch it without Console.
enum Log {
    static let app = Logger(subsystem: "com.connortan.lightswitch", category: "app")
    static let sensor = Logger(subsystem: "com.connortan.lightswitch", category: "sensor")
    static let sessions = Logger(subsystem: "com.connortan.lightswitch", category: "sessions")

    static let echo = ProcessInfo.processInfo.environment["LIGHTSWITCH_SNAPSHOT_DIR"] != nil

    static func note(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
        if echo {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
        }
    }
}
