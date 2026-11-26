import Foundation
import os
import ReadbackCore

/// Writes to the unified log and to ~/Library/Logs/Readback/readback.log, so failures
/// can be read later with a plain `tail`.
enum Log {
    private static let logger = Logger(subsystem: "local.readback", category: "app")
    private static let queue = DispatchQueue(label: "local.readback.log")
    static let directory = ReadbackPaths().logs
    private static let file = directory.appendingPathComponent("readback.log")

    static func info(_ message: String) { write("info", message); logger.info("\(message, privacy: .private)") }
    static func error(_ message: String) { write("error", message); logger.error("\(message, privacy: .private)") }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            do {
                try LogFile.append(line, to: file)
            } catch {
                logger.error("couldn't write log file: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
