import XCTest
@testable import Features
import Combine

@MainActor
final class UIStateManagerTests: XCTestCase {
    private var stateManager: UIStateManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        stateManager = UIStateManager.shared
        cancellables = []
        // Clear any existing state before each test
        stateManager.clearState()
    }

    override func tearDown() async throws {
        stateManager.clearState()
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Test In-Memory State Updates

    func testUpdateStateKeepsInMemory() async throws {
        // Create a test state
        let testState = UIState(
            tabs: [
                UIState.TabState(id: UUID(), title: "Tab 1", focusedNodeId: "node1"),
                UIState.TabState(id: UUID(), title: "Tab 2", focusedNodeId: "node2")
            ]
        )

        // Update state (should be instant, in-memory only)
        stateManager.updateState(testState)

        // Verify state is not immediately on disk by checking file doesn't exist
        // or hasn't been updated recently (within last 100ms)
        let fileURL = try getUIStateFileURL()

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modDate = attributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modDate)
                // File shouldn't have been modified in the last 100ms
                XCTAssertGreaterThan(timeSinceModification, 0.1,
                    "State was saved to disk immediately instead of being kept in memory")
            }
        }
    }

    func testSaveStateNowWritesToDisk() async throws {
        // Create a test state
        let testState = UIState(
            tabs: [
                UIState.TabState(id: UUID(), title: "Test Tab", focusedNodeId: "test-node")
            ]
        )

        // Update state and save immediately
        stateManager.updateState(testState)
        stateManager.saveStateNow()

        // Give it a moment to write
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Verify file exists and was recently modified
        let fileURL = try getUIStateFileURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
            "State file should exist after saveStateNow()")

        // Load and verify the state
        let loadedState = stateManager.loadState()
        XCTAssertNotNil(loadedState, "Should be able to load saved state")
        XCTAssertEqual(loadedState?.tabs.count, 1, "Should have one tab")
        XCTAssertEqual(loadedState?.tabs.first?.title, "Test Tab", "Tab title should match")
        XCTAssertEqual(loadedState?.tabs.first?.focusedNodeId, "test-node", "Focused node should match")
    }

    // MARK: - Test Periodic Saves

    func testPeriodicSaveOnlyOccursWhenStateChanges() async throws {
        let fileURL = try getUIStateFileURL()

        // Create initial state
        let state1 = UIState(
            tabs: [UIState.TabState(id: UUID(), title: "Tab 1", focusedNodeId: "node1")]
        )

        // Update and save state
        stateManager.updateState(state1)
        stateManager.saveStateNow()

        // Wait for save to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Get initial modification time
        let attributes1 = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modTime1 = attributes1[.modificationDate] as? Date
        XCTAssertNotNil(modTime1, "Should have modification date")

        // Update with same state multiple times
        stateManager.updateState(state1)
        stateManager.updateState(state1)
        stateManager.updateState(state1)

        // Wait for periodic save timer (1.5 seconds to ensure timer fired)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Check modification time hasn't changed (no save occurred)
        let attributes2 = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modTime2 = attributes2[.modificationDate] as? Date
        XCTAssertEqual(modTime1, modTime2,
            "File should not be re-saved when state hasn't changed")
    }

    func testPeriodicSaveOccursWithinOneSecond() async throws {
        let fileURL = try getUIStateFileURL()

        // Create and update state
        let state = UIState(
            tabs: [UIState.TabState(id: UUID(), title: "Test Tab", focusedNodeId: "node")]
        )
        stateManager.updateState(state)

        // Record start time
        let startTime = Date()

        // Wait up to 1.5 seconds for periodic save
        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds

        // Verify file exists and was saved within ~1 second
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
            "State should be saved by periodic timer")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let modTime = attributes[.modificationDate] as? Date {
            let timeSinceStart = modTime.timeIntervalSince(startTime)
            XCTAssertLessThanOrEqual(timeSinceStart, 1.5,
                "Periodic save should occur within ~1 second")
            XCTAssertGreaterThan(timeSinceStart, 0.3,
                "Periodic save should wait at least some of the interval")
        }
    }

    // MARK: - Test State Changes

    func testMultipleRapidUpdatesAreBatched() async throws {
        let fileURL = try getUIStateFileURL()

        // Make many rapid updates
        for i in 0..<10 {
            let state = UIState(
                tabs: [UIState.TabState(id: UUID(), title: "Tab \(i)", focusedNodeId: "node\(i)")]
            )
            stateManager.updateState(state)
            // Small delay between updates
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Record when updates finished
        let updatesFinishedTime = Date()

        // Wait for periodic save
        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds

        // Should have saved only once after all updates
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let modTime = attributes[.modificationDate] as? Date {
            let timeSinceUpdates = modTime.timeIntervalSince(updatesFinishedTime)
            XCTAssertGreaterThan(timeSinceUpdates, 0.5,
                "Save should be debounced, not immediate")
        }

        // Verify final state is correct
        let loadedState = stateManager.loadState()
        XCTAssertEqual(loadedState?.tabs.first?.title, "Tab 9",
            "Should have the last updated state")
    }

    // MARK: - Test Load and Clear

    func testLoadStateReturnsNilWhenNoSavedState() async throws {
        stateManager.clearState()
        let loadedState = stateManager.loadState()
        XCTAssertNil(loadedState, "Should return nil when no saved state exists")
    }

    func testClearStateRemovesFile() async throws {
        // Save a state
        let state = UIState(
            tabs: [UIState.TabState(id: UUID(), title: "Tab", focusedNodeId: nil)]
        )
        stateManager.updateState(state)
        stateManager.saveStateNow()

        // Wait for save
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify file exists
        let fileURL = try getUIStateFileURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Clear state
        stateManager.clearState()

        // Verify file is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
            "File should be removed after clearState()")

        // Verify load returns nil
        XCTAssertNil(stateManager.loadState(),
            "Should return nil after clearing state")
    }

    // MARK: - Test State Validation

    func testValidateStateRemovesDuplicateTabIds() async throws {
        let duplicateId = UUID()
        let state = UIState(
            tabs: [
                UIState.TabState(id: duplicateId, title: "Tab 1", focusedNodeId: nil),
                UIState.TabState(id: duplicateId, title: "Tab 2", focusedNodeId: nil),
                UIState.TabState(id: UUID(), title: "Tab 3", focusedNodeId: nil)
            ]
        )

        // Save state
        stateManager.updateState(state)
        stateManager.saveStateNow()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Load and validate
        let loadedState = stateManager.loadState()
        XCTAssertNotNil(loadedState)
        XCTAssertEqual(loadedState?.tabs.count, 2,
            "Should have removed duplicate tab ID")

        // Verify no duplicates
        let ids = loadedState?.tabs.map { $0.id } ?? []
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count,
            "All tab IDs should be unique")
    }

    func testValidateStateCreatesDefaultTabWhenEmpty() async throws {
        // Create state with no tabs
        let emptyState = UIState(tabs: [])

        // Save directly to file (bypassing validation in updateState)
        let fileURL = try getUIStateFileURL()
        let encoder = JSONEncoder()
        let data = try encoder.encode(emptyState)
        try data.write(to: fileURL)

        // Load and validate
        let loadedState = stateManager.loadState()
        XCTAssertNotNil(loadedState)
        XCTAssertEqual(loadedState?.tabs.count, 1,
            "Should create default tab when none exist")
        XCTAssertEqual(loadedState?.tabs.first?.title, "Main",
            "Default tab should be named 'Main'")
    }

    // MARK: - Helper Methods

    private func getUIStateFileURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("SwiftGTD")
        return appDirectory.appendingPathComponent("ui-state.json")
    }
}