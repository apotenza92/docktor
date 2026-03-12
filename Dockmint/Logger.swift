import Foundation
import os

/// Lightweight logger that writes to unified logging (os.Logger) and a per-run log file
/// under ~/Code/Dockmint/logs/Dockmint-<timestamp>.log so you can find it alongside the project.
enum Logger {
    private static let debugEnabled: Bool = {
        let environment = ProcessInfo.processInfo.environment
        let value = environment["DOCKMINT_DEBUG_LOG"] ?? environment["DOCKTOR_DEBUG_LOG"] ?? ""
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }()

    private static let oslog = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "pzc.Dockter",
        category: "general"
    )

    private static let queue = DispatchQueue(label: "com.dockappexpose.logger")
    private static let logDirectory: URL = {
        migrateLegacyLogDirectoryIfNeeded()
        return newLogDirectory
    }()

    private static let logURL: URL = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        return logDirectory.appendingPathComponent("Dockmint-\(stamp).log")
    }()

    static func log(_ message: String) {
        let line = "Dockmint: \(message)"
        oslog.log("\(line, privacy: .public)")
        NSLog("%@", line)
        queue.async {
            writeLine(line)
        }
    }

    static func debug(_ message: String) {
        guard debugEnabled else { return }
        let line = "Dockmint: \(message)"
        oslog.debug("\(line, privacy: .public)")
        queue.async {
            if let data = (line + "\n").data(using: .utf8) {
                try? FileHandle.standardError.write(contentsOf: data)
            }
            writeLine(line)
        }
    }

    private static func writeLine(_ line: String) {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: logDirectory.path) {
                try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            }
            let data = (line + "\n").data(using: .utf8) ?? Data()
            if fm.fileExists(atPath: logURL.path), let handle = try? FileHandle(forWritingTo: logURL) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Ignore file logging failures; keep the app running.
        }
    }

    private static func migrateLegacyLogDirectoryIfNeeded() {
        let fileManager = FileManager.default
        let oldDirectory = oldLogDirectory
        let newDirectory = newLogDirectory

        guard fileManager.fileExists(atPath: oldDirectory.path),
              !fileManager.fileExists(atPath: newDirectory.path) else {
            return
        }

        do {
            try fileManager.moveItem(at: oldDirectory, to: newDirectory)
        } catch {
            // Ignore directory migration failures; the logger will create the new path on demand.
        }
    }

    private static var oldLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Code/Docktor/logs")
    }

    private static var newLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Code/Dockmint/logs")
    }
}
