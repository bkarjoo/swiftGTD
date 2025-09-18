import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Compression

public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    var prefix: String {
        switch self {
        case .debug: return "🔍 DEBUG"
        case .info: return "ℹ️ INFO"
        case .warning: return "⚠️ WARN"
        case .error: return "❌ ERROR"
        }
    }
    
    var shortPrefix: String {
        switch self {
        case .debug: return "D"
        case .info: return "I"
        case .warning: return "W"
        case .error: return "E"
        }
    }
}

public class Logger {
    public static let shared = Logger()
    
    private let logDirectory: URL
    private let logFile: URL
    private let queue = DispatchQueue(label: "com.swiftgtd.logger", qos: .background)
    private var currentFileSize: Int64 = 0
    private let maxFileSize: Int64 = 10_000_000 // 10MB
    private let maxArchives = 5
    private var fileHandle: FileHandle?
    private let sessionID = UUID().uuidString.prefix(8)
    
    // Filtering
    public var minimumLevel: LogLevel = .debug
    public var enabledCategories: Set<String>? = nil // nil means all categories enabled
    
    // Console mirroring for DEBUG builds
    #if DEBUG
    private let mirrorToConsole = true
    #else
    private let mirrorToConsole = false
    #endif
    
    // Cached date formatters for performance
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
    
    private init() {
        // Use Application Support directory instead of Documents
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.logDirectory = appSupportPath.appendingPathComponent("Logs")
        
        // Create logs directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        
        self.logFile = logDirectory.appendingPathComponent("swiftgtd.log")
        
        // Rotate logs if file is too large
        rotateLogsIfNeeded()
        
        // Initialize file size
        updateFileSize()
        
        // Add detailed session separator
        addSessionBanner()
        
        // Setup notification observers for app lifecycle
        setupLifecycleObservers()
        
        // Set default log level based on build configuration
        #if DEBUG
        minimumLevel = .debug
        #else
        minimumLevel = .info
        #endif
    }
    
    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func applicationWillResignActive() {
        log("Application will resign active", level: .debug, category: "Lifecycle")
        flush()
    }
    
    @objc private func applicationWillTerminate() {
        log("Application will terminate", level: .debug, category: "Lifecycle")
        flush()
        closeFileHandle()
    }
    
    private func updateFileSize() {
        if FileManager.default.fileExists(atPath: logFile.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
                currentFileSize = attributes[.size] as? Int64 ?? 0
            } catch {
                currentFileSize = 0
            }
        } else {
            currentFileSize = 0
        }
    }
    
    private func rotateLogsIfNeeded() {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            // If file is larger than maxFileSize, rotate it
            if fileSize > maxFileSize {
                // Remove oldest archive if we're at max
                let oldestArchive = logDirectory.appendingPathComponent("swiftgtd.log.\(maxArchives).zlib")
                try? FileManager.default.removeItem(at: oldestArchive)
                
                // Shift existing archives
                for i in (1..<maxArchives).reversed() {
                    let oldPath = logDirectory.appendingPathComponent("swiftgtd.log.\(i).zlib")
                    let newPath = logDirectory.appendingPathComponent("swiftgtd.log.\(i+1).zlib")
                    if FileManager.default.fileExists(atPath: oldPath.path) {
                        try? FileManager.default.moveItem(at: oldPath, to: newPath)
                    }
                }
                
                // Compress and move current log to .1.gz
                let archivePath = logDirectory.appendingPathComponent("swiftgtd.log.1.zlib")
                compressFile(at: logFile, to: archivePath)
                try? FileManager.default.removeItem(at: logFile)
                
                currentFileSize = 0
            }
        } catch {
            // Ignore rotation errors
        }
    }
    
    private func compressFile(at source: URL, to destination: URL) {
        guard let sourceData = try? Data(contentsOf: source) else { return }
        
        let destinationData = sourceData.withUnsafeBytes { bytes -> Data? in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceData.count)
            defer { buffer.deallocate() }
            
            let compressedSize = compression_encode_buffer(
                buffer, sourceData.count,
                bytes.bindMemory(to: UInt8.self).baseAddress!, sourceData.count,
                nil, COMPRESSION_ZLIB
            )
            
            guard compressedSize > 0 else { return nil }
            return Data(bytes: buffer, count: compressedSize)
        }
        
        if let compressedData = destinationData {
            try? compressedData.write(to: destination)
        }
    }
    
    private func getDeviceInfo() -> String {
        #if canImport(UIKit)
        let device = UIDevice.current
        let systemVersion = device.systemVersion
        let deviceModel = device.model
        let deviceName = device.name
        return "\(deviceModel) '\(deviceName)' iOS \(systemVersion)"
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return "macOS \(osVersion)"
        #endif
    }
    
    private func getAppInfo() -> String {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SwiftGTD"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(appName) v\(appVersion) (Build \(buildNumber))"
    }
    
    private func addSessionBanner() {
        let timestamp = Logger.dateTimeFormatter.string(from: Date())
        let sessionMessage = """
        
        ════════════════════════════════════════════════════════════
        Session Started: \(timestamp)
        Session ID: \(sessionID)
        App: \(getAppInfo())
        Device: \(getDeviceInfo())
        Log Level: \(minimumLevel) (\(mirrorToConsole ? "Console Mirror ON" : "Console Mirror OFF"))
        ════════════════════════════════════════════════════════════
        
        """
        
        if let data = sessionMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
    
    public func log(_ message: String, level: LogLevel = .info, category: String = "General") {
        // Check if we should log based on level
        guard level >= minimumLevel else { return }
        
        // Check if category is enabled
        if let enabledCategories = enabledCategories, !enabledCategories.contains(category) {
            return
        }
        
        let timestamp = Logger.timeFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(sessionID)] [\(level.shortPrefix)] [\(category)] \(message)\n"
        
        // Mirror to console in DEBUG builds
        if mirrorToConsole {
            print("\(level.prefix) [\(category)] \(message)")
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if we need to rotate before writing
            if self.currentFileSize > self.maxFileSize {
                self.rotateLogsIfNeeded()
                self.updateFileSize()
            }
            
            if let data = logMessage.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: self.logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                        
                        // Update estimated file size
                        self.currentFileSize += Int64(data.count)
                    }
                } else {
                    try? data.write(to: self.logFile)
                    self.currentFileSize = Int64(data.count)
                }
            }
        }
    }
    
    // Convenience methods for different log levels
    public func debug(_ message: String, category: String = "General") {
        log(message, level: .debug, category: category)
    }
    
    public func info(_ message: String, category: String = "General") {
        log(message, level: .info, category: category)
    }
    
    public func warning(_ message: String, category: String = "General") {
        log(message, level: .warning, category: category)
    }
    
    public func error(_ message: String, category: String = "General") {
        log(message, level: .error, category: category)
    }
    
    public func flush() {
        queue.sync {
            // Force any pending writes to complete
            closeFileHandle()
        }
    }
    
    private func closeFileHandle() {
        fileHandle?.closeFile()
        fileHandle = nil
    }
    
    public func clearLog() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.closeFileHandle()
            try? FileManager.default.removeItem(at: self.logFile)
            self.currentFileSize = 0
        }
    }
    
    public func getLogPath() -> String {
        return logFile.path
    }
    
    public func getLogDirectory() -> String {
        return logDirectory.path
    }
    
    public func setLogLevel(_ level: LogLevel) {
        minimumLevel = level
        log("Log level changed to: \(level)", level: .info, category: "Logger")
    }
    
    public func enableCategories(_ categories: Set<String>?) {
        enabledCategories = categories
        if let categories = categories {
            log("Enabled categories: \(categories.joined(separator: ", "))", level: .info, category: "Logger")
        } else {
            log("All categories enabled", level: .info, category: "Logger")
        }
    }
    
    deinit {
        flush()
        closeFileHandle()
    }
}
