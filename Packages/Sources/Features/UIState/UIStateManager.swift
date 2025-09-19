import Foundation
import Core
import Combine

@MainActor
public class UIStateManager: ObservableObject {
    public static let shared = UIStateManager()
    private let logger = Logger.shared
    private let fileName = "ui-state.json"
    private let saveDebounceDelay: TimeInterval = 0.5 // 500ms debounce

    private var pendingState: UIState?
    private var saveTimer: Timer?
    private let saveQueue = DispatchQueue(label: "com.swiftgtd.uistate", qos: .background)

    private nonisolated var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("SwiftGTD")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appDirectory,
                                                withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent(fileName)
    }

    private init() {}

    // Debounced save - queues the state and saves after delay
    public func saveState(_ state: UIState) {
        logger.log("📝 Queueing UI state save with \(state.tabs.count) tabs", category: "UIStateManager")

        // Store the pending state
        pendingState = state

        // Cancel existing timer
        saveTimer?.invalidate()

        // Schedule new save after delay
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSave()
            }
        }
    }

    // Force immediate save (for app termination)
    public func saveStateImmediately(_ state: UIState) {
        logger.log("💾 Immediate save requested", category: "UIStateManager")
        saveTimer?.invalidate()
        pendingState = state
        performSaveSync()
    }

    private func performSave() {
        guard let state = pendingState else { return }

        logger.log("💾 Performing UI state save with \(state.tabs.count) tabs", category: "UIStateManager")

        // Perform save on background queue
        saveQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(state)

                // Atomic write: write to temp file first, then move
                let tempURL = self.fileURL.appendingPathExtension("tmp")
                try data.write(to: tempURL, options: .atomic)

                // Move temp file to final location (atomic operation)
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    try FileManager.default.removeItem(at: self.fileURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: self.fileURL)

                Task { @MainActor in
                    self.logger.log("✅ UI state saved successfully", category: "UIStateManager")
                }
            } catch {
                Task { @MainActor in
                    self.logger.error("❌ Failed to save UI state: \(error)", category: "UIStateManager")
                }
            }
        }
    }

    // Synchronous save for termination/background cases
    private func performSaveSync() {
        guard let state = pendingState else { return }

        logger.log("💾 Performing synchronous UI state save with \(state.tabs.count) tabs", category: "UIStateManager")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)

            // Atomic write: write to temp file first, then move
            let tempURL = self.fileURL.appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)

            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                try FileManager.default.removeItem(at: self.fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: self.fileURL)

            logger.log("✅ UI state saved synchronously", category: "UIStateManager")
        } catch {
            logger.error("❌ Failed to synchronously save UI state: \(error)", category: "UIStateManager")
        }
    }

    public func loadState() -> UIState? {
        logger.log("📂 Loading UI state from: \(fileURL.path)", category: "UIStateManager")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.log("ℹ️ No saved UI state found", category: "UIStateManager")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(UIState.self, from: data)

            // Validate the loaded state
            let validatedState = validateState(state)

            logger.log("✅ Loaded UI state with \(validatedState.tabs.count) tabs", category: "UIStateManager")
            return validatedState
        } catch {
            logger.error("❌ Failed to load UI state: \(error)", category: "UIStateManager")
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

    public func clearState() {
        logger.log("🗑️ Clearing UI state", category: "UIStateManager")

        // Cancel any pending saves
        saveTimer?.invalidate()
        pendingState = nil

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                logger.log("✅ UI state cleared", category: "UIStateManager")
            } catch {
                logger.error("❌ Failed to clear UI state: \(error)", category: "UIStateManager")
            }
        }
    }
}
