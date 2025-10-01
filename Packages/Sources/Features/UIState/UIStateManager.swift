import Foundation
import Core
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
public class UIStateManager: ObservableObject {
    public static let shared = UIStateManager()
    private let logger = Logger.shared
    private let fileNamePrefix = "ui-state"
    private let periodicSaveInterval: TimeInterval = 1.0 // Save at most once per second

    private var windowStates: [UUID: UIState] = [:] // Per-window state
    private var lastSavedStates: [UUID: UIState] = [:] // Track what was last saved to disk
    private var periodicSaveTimer: Timer?
    private let saveQueue = DispatchQueue(label: "com.swiftgtd.uistate", qos: .background)

    private nonisolated func fileURL(for windowId: UUID) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("SwiftGTD")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appDirectory,
                                                withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent("\(fileNamePrefix)-\(windowId.uuidString).json")
    }

    private nonisolated var statesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("SwiftGTD")
        try? FileManager.default.createDirectory(at: appDirectory,
                                                withIntermediateDirectories: true)
        return appDirectory
    }

    private init() {
        // Start periodic save timer
        startPeriodicSaveTimer()

        // Listen for app termination
        #if os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }

    deinit {
        periodicSaveTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // Update in-memory state (instant, no disk I/O)
    public func updateState(_ state: UIState, for windowId: UUID) {
        windowStates[windowId] = state
    }

    // Save state at key moments (tab change, window deactivation, etc)
    public func saveStateNow(for windowId: UUID) {
        guard let state = windowStates[windowId] else { return }
        performSave(state, for: windowId)
    }

    // Remove state when window closes
    public func removeState(for windowId: UUID) {
        windowStates.removeValue(forKey: windowId)
        lastSavedStates.removeValue(forKey: windowId)

        // Delete the file
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.fileURL(for: windowId)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // Periodic save timer - runs every second but only saves if state changed
    private func startPeriodicSaveTimer() {
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: periodicSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performPeriodicSave()
            }
        }
    }

    private func performPeriodicSave() {
        // Save all windows that have changed
        for (windowId, state) in windowStates {
            let lastSaved = lastSavedStates[windowId]
            if !stateEquals(state, lastSaved) {
                performSave(state, for: windowId)
            }
        }
    }

    private func stateEquals(_ state1: UIState?, _ state2: UIState?) -> Bool {
        guard let s1 = state1, let s2 = state2 else { return state1 == nil && state2 == nil }
        // Compare the encoded JSON to detect any changes
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data1 = try? encoder.encode(s1),
              let data2 = try? encoder.encode(s2) else { return false }
        return data1 == data2
    }

    @objc private func applicationWillTerminate() {
        // Save all windows immediately on termination
        for (windowId, state) in windowStates {
            performSaveSync(state, for: windowId)
        }
    }

    private func performSave(_ state: UIState, for windowId: UUID) {
        logger.log("💾 Performing UI state save for window \(windowId) with \(state.tabs.count) tabs", category: "UIStateManager")

        // Perform save on background queue
        saveQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(state)

                let url = self.fileURL(for: windowId)
                // Atomic write: write to temp file first, then move
                let tempURL = url.appendingPathExtension("tmp")
                try data.write(to: tempURL, options: .atomic)

                // Move temp file to final location (atomic operation)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: tempURL, to: url)

                Task { @MainActor in
                    self.logger.log("✅ UI state saved successfully for window \(windowId)", category: "UIStateManager")
                    self.lastSavedStates[windowId] = state
                }
            } catch {
                Task { @MainActor in
                    self.logger.error("❌ Failed to save UI state for window \(windowId): \(error)", category: "UIStateManager")
                }
            }
        }
    }

    // Synchronous save for termination/background cases
    private func performSaveSync(_ state: UIState, for windowId: UUID) {
        logger.log("💾 Performing synchronous UI state save for window \(windowId) with \(state.tabs.count) tabs", category: "UIStateManager")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)

            let url = fileURL(for: windowId)
            // Atomic write: write to temp file first, then move
            let tempURL = url.appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)

            logger.log("✅ UI state saved synchronously for window \(windowId)", category: "UIStateManager")
            lastSavedStates[windowId] = state
        } catch {
            logger.error("❌ Failed to synchronously save UI state for window \(windowId): \(error)", category: "UIStateManager")
        }
    }

    public func loadState(for windowId: UUID) -> UIState? {
        let url = fileURL(for: windowId)
        logger.log("📂 Loading UI state for window \(windowId) from: \(url.path)", category: "UIStateManager")

        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.log("ℹ️ No saved UI state found for window \(windowId)", category: "UIStateManager")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(UIState.self, from: data)

            // Validate the loaded state
            let validatedState = validateState(state)

            logger.log("✅ Loaded UI state for window \(windowId) with \(validatedState.tabs.count) tabs", category: "UIStateManager")
            return validatedState
        } catch {
            logger.error("❌ Failed to load UI state for window \(windowId): \(error)", category: "UIStateManager")
            return nil
        }
    }

    // Load any existing window state (for creating first window)
    public func loadAnyExistingState() -> UIState? {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: statesDirectory,
                                                                    includingPropertiesForKeys: nil)
            let stateFiles = files.filter { $0.lastPathComponent.hasPrefix(fileNamePrefix) && $0.pathExtension == "json" }

            // Use the most recently modified state file
            let sortedFiles = stateFiles.sorted { (url1, url2) -> Bool in
                let date1 = (try? FileManager.default.attributesOfItem(atPath: url1.path)[.modificationDate] as? Date) ?? Date.distantPast
                let date2 = (try? FileManager.default.attributesOfItem(atPath: url2.path)[.modificationDate] as? Date) ?? Date.distantPast
                return date1 > date2
            }

            guard let mostRecentFile = sortedFiles.first else { return nil }

            let data = try Data(contentsOf: mostRecentFile)
            let state = try JSONDecoder().decode(UIState.self, from: data)
            return validateState(state)
        } catch {
            logger.error("❌ Failed to load any existing state: \(error)", category: "UIStateManager")
            return nil
        }
    }

    private func validateState(_ state: UIState) -> UIState {
        // Check for duplicate tab IDs
        var seenIds = Set<UUID>()
        var validTabs: [UIState.TabState] = []

        for tab in state.tabs {
            if !seenIds.contains(tab.id) {
                seenIds.insert(tab.id)
                validTabs.append(tab)
            } else {
                logger.log("⚠️ Skipping duplicate tab ID: \(tab.id)", category: "UIStateManager")
            }
        }

        // Ensure at least one tab exists
        if validTabs.isEmpty {
            logger.log("⚠️ No valid tabs found, creating default tab", category: "UIStateManager")
            validTabs = [UIState.TabState(id: UUID(), title: "Main")]
        }

        // Check version compatibility
        if state.version > UIState.currentVersion {
            logger.log("⚠️ State version \(state.version) is newer than current version \(UIState.currentVersion)", category: "UIStateManager")
            // In the future, we might need migration logic here
        }

        return UIState(tabs: validTabs, version: state.version)
    }

    public func clearState(for windowId: UUID) {
        logger.log("🗑️ Clearing UI state for window \(windowId)", category: "UIStateManager")

        // Clear in-memory state
        windowStates.removeValue(forKey: windowId)
        lastSavedStates.removeValue(forKey: windowId)

        let url = fileURL(for: windowId)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                logger.log("✅ UI state cleared for window \(windowId)", category: "UIStateManager")
            } catch {
                logger.error("❌ Failed to clear UI state for window \(windowId): \(error)", category: "UIStateManager")
            }
        }
    }

    public func clearAllStates() {
        logger.log("🗑️ Clearing all UI states", category: "UIStateManager")

        windowStates.removeAll()
        lastSavedStates.removeAll()

        do {
            let files = try FileManager.default.contentsOfDirectory(at: statesDirectory,
                                                                    includingPropertiesForKeys: nil)
            let stateFiles = files.filter { $0.lastPathComponent.hasPrefix(fileNamePrefix) && $0.pathExtension == "json" }

            for file in stateFiles {
                try FileManager.default.removeItem(at: file)
            }
            logger.log("✅ All UI states cleared", category: "UIStateManager")
        } catch {
            logger.error("❌ Failed to clear all UI states: \(error)", category: "UIStateManager")
        }
    }
}
