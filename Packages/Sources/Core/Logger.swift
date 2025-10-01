import Foundation
import os.log

/// Log levels for filtering messages
public enum LogLevel: Int, Comparable, CaseIterable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case fault = 5

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .fault:
            return .fault
        }
    }

    var emoji: String {
        switch self {
        case .verbose:
            return "🔍"
        case .debug:
            return "🐛"
        case .info:
            return "ℹ️"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        case .fault:
            return "💥"
        }
    }

    var name: String {
        switch self {
        case .verbose:
            return "VERBOSE"
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        }
    }
}

/// A robust logger that uses Apple's unified logging system with file fallback
public final class Logger {
    public static let shared = Logger()

    // MARK: - Properties

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.swiftgtd.SwiftGTD"
    private var osLoggers: [String: OSLog] = [:]
    private let queue = DispatchQueue(label: "com.swiftgtd.logger", qos: .utility)

    // File logging
    private let fileLogEnabled: Bool
    private let logFileURL: URL?
    private let maxLogFileSize: Int = 10_000_000 // 10MB
    private let maxLogFiles: Int = 5

    // Filtering
    public var minimumLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    public var enabledCategories: Set<String>?

    // Console output for debugging
    #if DEBUG
    private let consoleOutputEnabled = true
    #else
    private let consoleOutputEnabled = false
    #endif

    // MARK: - Initialization

    private init() {
        // Setup file logging
        #if os(iOS) || os(macOS)
        self.fileLogEnabled = true
        self.logFileURL = Logger.setupFileLogging()
        #else
        self.fileLogEnabled = false
        self.logFileURL = nil
        #endif

        // Log startup
        self.log("Logger initialized", category: "Logger", level: .info)
        self.logSystemInfo()
    }

    // MARK: - OS Log Management

    private func getOSLog(for category: String) -> OSLog {
        return queue.sync {
            if let logger = osLoggers[category] {
                return logger
            }
            let logger = OSLog(subsystem: subsystem, category: category)
            osLoggers[category] = logger
            return logger
        }
    }

    // MARK: - Main Logging Function

    public func log(
        _ message: String,
        category: String = "General",
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Check level filter
        guard level >= minimumLevel else { return }

        // Check category filter
        if let enabledCategories = enabledCategories,
           !enabledCategories.contains(category) {
            return
        }

        // Extract filename from path
        let filename = (file as NSString).lastPathComponent

        // Create the log message
        let logMessage = formatMessage(
            message,
            category: category,
            level: level,
            file: filename,
            function: function,
            line: line
        )

        // Log to os.log
        let osLog = getOSLog(for: category)
        os_log("%{public}@", log: osLog, type: level.osLogType, logMessage)

        // Log to console in debug builds
        if consoleOutputEnabled {
            print(logMessage)
        }

        // Log to file
        if fileLogEnabled {
            writeToFile(logMessage)
        }
    }

    // MARK: - Convenience Methods

    public func verbose(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .verbose, file: file, function: function, line: line)
    }

    public func debug(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .debug, file: file, function: function, line: line)
    }

    public func info(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .info, file: file, function: function, line: line)
    }

    public func warning(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .warning, file: file, function: function, line: line)
    }

    public func error(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .error, file: file, function: function, line: line)
    }

    public func fault(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .fault, file: file, function: function, line: line)
    }

    // MARK: - Message Formatting

    private func formatMessage(
        _ message: String,
        category: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        #if DEBUG
        // Include file info in debug builds
        return "\(level.emoji) [\(timestamp)] [\(category)] [\(level.name)] \(message) [\(file):\(line) \(function)]"
        #else
        // Simpler format for release builds
        return "\(level.emoji) [\(timestamp)] [\(category)] [\(level.name)] \(message)"
        #endif
    }

    // MARK: - File Logging

    private static func setupFileLogging() -> URL? {
        let fileManager = FileManager.default

        // Get the appropriate directory based on platform
        #if os(macOS)
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        #else
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appSupport = documentsDir
        #endif

        // Create logs directory
        let logsDir = appSupport.appendingPathComponent("Logs")
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)

        return logsDir.appendingPathComponent("swiftgtd.log")
    }

    private func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        queue.async {
            let messageWithNewline = message + "\n"

            do {
                // Check if file exists
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    // Check file size and rotate if needed
                    let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
                    if let fileSize = attributes[.size] as? Int, fileSize > self.maxLogFileSize {
                        self.rotateLogFiles()
                    }

                    // Append to existing file
                    if let handle = try? FileHandle(forWritingTo: logFileURL) {
                        handle.seekToEndOfFile()
                        if let data = messageWithNewline.data(using: .utf8) {
                            handle.write(data)
                        }
                        handle.closeFile()
                    }
                } else {
                    // Create new file
                    try messageWithNewline.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                // Silently fail - we don't want logging to crash the app
            }
        }
    }

    private func rotateLogFiles() {
        guard let logFileURL = logFileURL else { return }
        let fileManager = FileManager.default
        let logDir = logFileURL.deletingLastPathComponent()
        let baseName = logFileURL.deletingPathExtension().lastPathComponent
        let ext = logFileURL.pathExtension

        // Remove oldest file
        let oldestFile = logDir.appendingPathComponent("\(baseName).\(maxLogFiles).\(ext)")
        try? fileManager.removeItem(at: oldestFile)

        // Rotate existing files
        for i in (1..<maxLogFiles).reversed() {
            let oldURL = logDir.appendingPathComponent("\(baseName).\(i).\(ext)")
            let newURL = logDir.appendingPathComponent("\(baseName).\(i + 1).\(ext)")
            if fileManager.fileExists(atPath: oldURL.path) {
                try? fileManager.moveItem(at: oldURL, to: newURL)
            }
        }

        // Move current log to .1
        let firstArchive = logDir.appendingPathComponent("\(baseName).1.\(ext)")
        try? fileManager.moveItem(at: logFileURL, to: firstArchive)
    }

    // MARK: - System Information

    private func logSystemInfo() {
        let processInfo = ProcessInfo.processInfo

        log("═══════════════════════════════════════════════════", category: "System", level: .info)
        log("App: \(Bundle.main.bundleIdentifier ?? "Unknown")", category: "System", level: .info)
        log("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")", category: "System", level: .info)
        log("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")", category: "System", level: .info)
        log("OS: \(processInfo.operatingSystemVersionString)", category: "System", level: .info)
        log("Device: \(getDeviceName())", category: "System", level: .info)
        log("Process: \(processInfo.processName) [\(processInfo.processIdentifier)]", category: "System", level: .info)
        log("═══════════════════════════════════════════════════", category: "System", level: .info)
    }

    private func getDeviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(iOS)
        return UIDevice.current.name
        #else
        return "Unknown Device"
        #endif
    }

    // MARK: - Configuration

    public func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
        log("Minimum log level set to: \(level.name)", category: "Logger", level: .info)
    }

    public func setEnabledCategories(_ categories: Set<String>?) {
        enabledCategories = categories
        if let categories = categories {
            log("Enabled categories: \(categories.joined(separator: ", "))", category: "Logger", level: .info)
        } else {
            log("All categories enabled", category: "Logger", level: .info)
        }
    }

    // MARK: - Utility

    public func getLogFileURL() -> URL? {
        return logFileURL
    }

    public func getLogFilePath() -> String? {
        return logFileURL?.path
    }

    public func clearLogs() {
        guard let logFileURL = logFileURL else { return }

        queue.async {
            let fileManager = FileManager.default
            let logDir = logFileURL.deletingLastPathComponent()

            // Remove all log files
            if let enumerator = fileManager.enumerator(at: logDir, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.hasPrefix("swiftgtd") {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }

            self.log("All logs cleared", category: "Logger", level: .info)
        }
    }

    public func exportLogs() -> Data? {
        guard let logFileURL = logFileURL else { return nil }

        return queue.sync {
            var combinedLogs = ""
            let fileManager = FileManager.default
            let logDir = logFileURL.deletingLastPathComponent()

            // Collect all log files
            var logFiles: [URL] = []
            if let enumerator = fileManager.enumerator(at: logDir, includingPropertiesForKeys: [.creationDateKey]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.hasPrefix("swiftgtd") && fileURL.pathExtension == "log" {
                        logFiles.append(fileURL)
                    }
                }
            }

            // Sort by creation date
            logFiles.sort { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 < date2
            }

            // Combine all logs
            for fileURL in logFiles {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    combinedLogs += "═══ \(fileURL.lastPathComponent) ═══\n"
                    combinedLogs += content
                    combinedLogs += "\n\n"
                }
            }

            return combinedLogs.data(using: .utf8)
        }
    }
}

// MARK: - Extensions

#if os(macOS)
import AppKit

extension Logger {
    public func logViewHierarchy(for view: NSView, indent: Int = 0) {
        let indentStr = String(repeating: "  ", count: indent)
        let viewInfo = "\(indentStr)\(type(of: view)): frame=\(view.frame), hidden=\(view.isHidden)"
        debug(viewInfo, category: "ViewHierarchy")

        for subview in view.subviews {
            logViewHierarchy(for: subview, indent: indent + 1)
        }
    }
}
#endif

#if os(iOS)
import UIKit

extension Logger {
    public func logViewHierarchy(for view: UIView, indent: Int = 0) {
        let indentStr = String(repeating: "  ", count: indent)
        let viewInfo = "\(indentStr)\(type(of: view)): frame=\(view.frame), hidden=\(view.isHidden)"
        debug(viewInfo, category: "ViewHierarchy")

        for subview in view.subviews {
            logViewHierarchy(for: subview, indent: indent + 1)
        }
    }
}
#endif