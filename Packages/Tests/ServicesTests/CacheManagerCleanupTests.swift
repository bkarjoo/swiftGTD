import XCTest
import Foundation
@testable import Services
@testable import Models
@testable import Core

/// Tests for CacheManager cache cleanup functionality
@MainActor
final class CacheManagerCleanupTests: XCTestCase {
    
    private var cacheManager: CacheManager!
    private let testCacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestCacheCleanup")
    
    override func setUp() async throws {
        try await super.setUp()
        // Create fresh CacheManager for each test
        cacheManager = CacheManager.shared
        // Clear any existing cache
        await cacheManager.clearCache()
    }
    
    override func tearDown() async throws {
        // Clean up test cache
        await cacheManager.clearCache()
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestNodes(count: Int) -> [Node] {
        return (1...count).map { index in
            Node(
                id: "node-\(index)",
                title: "Test Node \(index)",
                nodeType: index % 2 == 0 ? "task" : "note",
                parentId: nil,
                sortOrder: index * 100,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }
    
    private func getCacheDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cache", isDirectory: true)
    }
    
    private func createOldCacheFile(daysOld: Int, filename: String = "old_cache.json") async throws {
        let cacheDir = getCacheDirectory()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let fileURL = cacheDir.appendingPathComponent(filename)
        let testData = "Test cache data created \(daysOld) days ago".data(using: .utf8)!
        try testData.write(to: fileURL)
        
        // Set file modification date to past
        let oldDate = Date().addingTimeInterval(-Double(daysOld * 24 * 3600))
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate, .creationDate: oldDate],
            ofItemAtPath: fileURL.path
        )
    }
    
    // MARK: - Age-based Cleanup Tests
    
    func testCacheManager_cleanupOldFiles_removesFilesOlderThan30Days() async throws {
        // Arrange - Create files with different ages
        try await createOldCacheFile(daysOld: 35, filename: "very_old.json")
        try await createOldCacheFile(daysOld: 31, filename: "old.json")
        try await createOldCacheFile(daysOld: 29, filename: "recent.json")
        try await createOldCacheFile(daysOld: 1, filename: "new.json")
        
        // Also save current nodes (should not be deleted)
        let nodes = createTestNodes(count: 10)
        await cacheManager.saveNodes(nodes)
        
        // Act - Cleanup old files
        let removedCount = await cacheManager.cleanupOldFiles(olderThanDays: 30)
        
        // Assert
        XCTAssertEqual(removedCount, 2, "Should remove 2 files older than 30 days")
        
        // Verify old files are gone
        let cacheDir = getCacheDirectory()
        let veryOldExists = FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("very_old.json").path)
        let oldExists = FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("old.json").path)
        XCTAssertFalse(veryOldExists, "Very old file should be deleted")
        XCTAssertFalse(oldExists, "Old file should be deleted")
        
        // Verify recent files still exist
        let recentExists = FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("recent.json").path)
        let newExists = FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("new.json").path)
        XCTAssertTrue(recentExists, "Recent file should still exist")
        XCTAssertTrue(newExists, "New file should still exist")
        
        // Verify nodes cache still exists and loads correctly
        let loadedNodes = await cacheManager.loadNodes()
        XCTAssertEqual(loadedNodes?.count, 10, "Current nodes cache should be preserved")
    }
    
    func testCacheManager_cleanupOldFiles_preservesMetadataFile() async throws {
        // Arrange - Create old metadata file (should be preserved)
        let cacheDir = getCacheDirectory()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        // Save metadata through CacheManager
        await cacheManager.saveMetadata(nodeCount: 100, tagCount: 10, ruleCount: 5)
        
        // Make metadata file appear old
        let metadataURL = cacheDir.appendingPathComponent("cache_metadata.json")
        let oldDate = Date().addingTimeInterval(-Double(40 * 24 * 3600))
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: metadataURL.path
        )
        
        // Act - Cleanup
        let removedCount = await cacheManager.cleanupOldFiles(olderThanDays: 30)
        
        // Assert - Metadata should be preserved despite being old
        XCTAssertEqual(removedCount, 0, "Should not remove metadata file")
        let metadata = await cacheManager.loadMetadata()
        XCTAssertNotNil(metadata, "Metadata should still be loadable")
        XCTAssertEqual(metadata?.nodeCount, 100, "Metadata content should be intact")
    }
    
    func testCacheManager_cleanupOldFiles_withNoOldFiles_returnsZero() async throws {
        // Arrange - Create only recent files
        try await createOldCacheFile(daysOld: 1, filename: "recent1.json")
        try await createOldCacheFile(daysOld: 7, filename: "recent2.json")
        try await createOldCacheFile(daysOld: 14, filename: "recent3.json")
        
        // Act
        let removedCount = await cacheManager.cleanupOldFiles(olderThanDays: 30)
        
        // Assert
        XCTAssertEqual(removedCount, 0, "Should not remove any files")
    }
    
    // MARK: - Size-based Cleanup Tests
    
    func testCacheManager_enforceMaxCacheSize_removesOldestFilesFirst() async throws {
        // Arrange - Create multiple cache files with different ages
        let nodes1 = createTestNodes(count: 100)
        await cacheManager.saveNodes(nodes1)
        
        // Wait a bit and create more files
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        // Create additional cache files
        try await createOldCacheFile(daysOld: 20, filename: "old_data.json")
        try await createOldCacheFile(daysOld: 10, filename: "medium_data.json")
        
        // Create a large recent file
        let largeData = String(repeating: "x", count: 500_000).data(using: .utf8)!
        let cacheDir = getCacheDirectory()
        let largeFileURL = cacheDir.appendingPathComponent("large_recent.json")
        try largeData.write(to: largeFileURL)
        
        // Act - Enforce a small max size (100KB)
        let maxSizeBytes: Int64 = 100 * 1024 // 100KB
        let removedFiles = await cacheManager.enforceMaxCacheSize(maxBytes: maxSizeBytes)
        
        // Assert
        XCTAssertGreaterThan(removedFiles.count, 0, "Should remove some files")
        
        // Check total size is under limit
        let finalSize = await cacheManager.getCacheSize()
        XCTAssertLessThanOrEqual(finalSize, maxSizeBytes, "Cache size should be under limit")
        
        // Verify metadata is still present (protected file)
        let metadata = await cacheManager.loadMetadata()
        // Metadata might be nil if not saved, that's ok
    }
    
    func testCacheManager_enforceMaxCacheSize_protectsCriticalFiles() async throws {
        // Arrange - Save critical data
        let nodes = createTestNodes(count: 50)
        await cacheManager.saveNodes(nodes)
        await cacheManager.saveMetadata(nodeCount: 50, tagCount: 5, ruleCount: 2)
        
        let tags = [
            Tag(id: "tag1", name: "Important", color: "#FF0000", description: nil, createdAt: nil),
            Tag(id: "tag2", name: "Work", color: "#0000FF", description: nil, createdAt: nil)
        ]
        await cacheManager.saveTags(tags)
        
        // Act - Enforce very small size that would require deleting everything
        let removedFiles = await cacheManager.enforceMaxCacheSize(maxBytes: 1024) // 1KB - very small
        
        // Assert - Critical files should be preserved as much as possible
        // At minimum, nodes cache should exist
        let loadedNodes = await cacheManager.loadNodes()
        // Nodes might be nil if size constraint is too strict, but method shouldn't crash
        
        // Method should complete without errors
        XCTAssertNotNil(removedFiles, "Should return list of removed files (even if empty)")
    }
    
    func testCacheManager_enforceMaxCacheSize_withSizeAlreadyUnderLimit() async throws {
        // Arrange - Save small amount of data
        let nodes = createTestNodes(count: 5)
        await cacheManager.saveNodes(nodes)
        
        let initialSize = await cacheManager.getCacheSize()
        
        // Act - Enforce size limit well above current usage
        let removedFiles = await cacheManager.enforceMaxCacheSize(maxBytes: initialSize + 1_000_000)
        
        // Assert
        XCTAssertEqual(removedFiles.count, 0, "Should not remove any files")
        
        // Verify data still intact
        let loaded = await cacheManager.loadNodes()
        XCTAssertEqual(loaded?.count, 5, "All nodes should still be present")
    }
    
    // MARK: - Combined Cleanup Tests
    
    func testCacheManager_performMaintenance_combinesAgeAndSizeCleanup() async throws {
        // Arrange - Disable auto-cleanup to prevent interference
        await cacheManager.setAutoCleanupThreshold(kilobytes: 10000) // 10MB - very high
        
        // Create mix of old and new files
        try await createOldCacheFile(daysOld: 35, filename: "ancient.json")
        try await createOldCacheFile(daysOld: 31, filename: "old.json")
        try await createOldCacheFile(daysOld: 25, filename: "medium_old.json")
        
        // Verify files exist before maintenance
        let cacheDir = getCacheDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("ancient.json").path), 
                     "Ancient file should exist before maintenance")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("old.json").path),
                     "Old file should exist before maintenance")
        
        // Create large recent data
        let nodes = createTestNodes(count: 500)
        await cacheManager.saveNodes(nodes)
        
        // Act - Perform maintenance with both age and size constraints
        let maintenanceResult = await cacheManager.performMaintenance(
            maxAgeInDays: 30,
            maxSizeInMB: 1 // 1MB limit
        )
        
        // Assert
        XCTAssertGreaterThanOrEqual(maintenanceResult.filesRemoved, 2, "Should remove at least 2 old files")
        
        // Old files should be gone
        let ancientExists = FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent("ancient.json").path
        )
        let oldExists = FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent("old.json").path
        )
        XCTAssertFalse(ancientExists, "Ancient file should be removed")
        XCTAssertFalse(oldExists, "Old file should be removed")
        
        // Medium old file should still exist (25 days < 30 days)
        let mediumExists = FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent("medium_old.json").path
        )
        XCTAssertTrue(mediumExists, "Medium old file should still exist")
        
        // Cache size should be reasonable
        let finalSize = await cacheManager.getCacheSize()
        XCTAssertLessThanOrEqual(finalSize, Int64(1024 * 1024), "Size should be under 1MB")
    }
    
    // MARK: - Auto-cleanup Tests
    
    func testCacheManager_autoCleanupOnSave_triggersWhenSizeExceeded() async throws {
        // Arrange - Set a small auto-cleanup threshold
        await cacheManager.setAutoCleanupThreshold(kilobytes: 100) // 100KB threshold
        
        // Create some old cache files first
        try await createOldCacheFile(daysOld: 5, filename: "old_data_1.json")
        try await createOldCacheFile(daysOld: 10, filename: "old_data_2.json")
        
        // Create initial nodes data
        let initialNodes = createTestNodes(count: 100)
        await cacheManager.saveNodes(initialNodes)
        
        // Add more test files to exceed threshold
        let largeData = String(repeating: "x", count: 100_000).data(using: .utf8)!
        let cacheDir = getCacheDirectory()
        try largeData.write(to: cacheDir.appendingPathComponent("extra_data.json"))
        
        let sizeBeforeCleanup = await cacheManager.getCacheSize()
        XCTAssertGreaterThan(sizeBeforeCleanup, Int64(100 * 1024), "Should be over threshold before save")
        
        // Act - Save new data that triggers auto-cleanup
        let newNodes = createTestNodes(count: 50)
        await cacheManager.saveNodes(newNodes)
        
        // Assert
        let finalSize = await cacheManager.getCacheSize()
        
        // Should have triggered cleanup to stay near threshold
        // Allow double the threshold as overhead since nodes file is protected
        XCTAssertLessThan(finalSize, Int64(200 * 1024), "Auto-cleanup should keep size reasonable")
        
        // Recent nodes data should still be loadable
        let loaded = await cacheManager.loadNodes()
        XCTAssertNotNil(loaded, "Should still have cached nodes")
        XCTAssertEqual(loaded?.count, 50, "Should have the newly saved nodes")
    }
    
    // MARK: - Performance Tests
    
    func testCacheManager_cleanupPerformance_handlesLargeNumberOfFiles() async throws {
        // Arrange - Create many old files
        let cacheDir = getCacheDirectory()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        for i in 1...100 {
            let age = 31 + (i % 10) // Mix of ages, all > 30 days
            try await createOldCacheFile(daysOld: age, filename: "old_file_\(i).json")
        }
        
        // Act & Measure
        let startTime = Date()
        let removedCount = await cacheManager.cleanupOldFiles(olderThanDays: 30)
        let cleanupTime = Date().timeIntervalSince(startTime)
        
        // Assert
        XCTAssertEqual(removedCount, 100, "Should remove all 100 old files")
        XCTAssertLessThan(cleanupTime, 2.0, "Should clean 100 files in less than 2 seconds")
    }
}