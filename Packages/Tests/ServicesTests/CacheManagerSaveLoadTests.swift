import XCTest
import Foundation
@testable import Services
@testable import Models
@testable import Core

/// Tests for CacheManager save/load functionality
@MainActor
final class CacheManagerSaveLoadTests: XCTestCase {
    
    private var cacheManager: CacheManager!
    private let testCacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestCache")
    
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
    
    private func createTestNode(id: String, title: String, type: String = "task") -> Node {
        return Node(
            id: id,
            title: title,
            nodeType: type,
            parentId: nil,
            sortOrder: Int.random(in: 1000...9000),
            createdAt: Date().addingTimeInterval(-Double.random(in: 0...86400)),
            updatedAt: Date(),
            taskData: type == "task" ? TaskData(
                description: "Description for \(title)",
                status: Bool.random() ? "done" : "todo",
                priority: ["high", "medium", "low"].randomElement(),
                completedAt: Bool.random() ? ISO8601DateFormatter().string(from: Date()) : nil
            ) : nil,
            noteData: type == "note" ? NoteData(body: "Note body for \(title)") : nil
        )
    }
    
    private func createLargeNodeSet(count: Int) -> [Node] {
        return (1...count).map { index in
            let types = ["task", "note", "folder", "project"]
            let type = types[index % types.count]
            return createTestNode(
                id: "node-\(index)",
                title: "Test Node \(index)",
                type: type
            )
        }
    }
    
    // MARK: - Save/Load Tests
    
    func testCacheManager_saveAndLoadNodes_withSmallSet() async throws {
        // Arrange
        let nodes = [
            createTestNode(id: "1", title: "Task 1"),
            createTestNode(id: "2", title: "Note 1", type: "note"),
            createTestNode(id: "3", title: "Folder 1", type: "folder")
        ]
        
        // Act - Save
        await cacheManager.saveNodes(nodes)
        
        // Act - Load
        let loadedNodes = await cacheManager.loadNodes()
        
        // Assert
        XCTAssertNotNil(loadedNodes, "Should load nodes")
        XCTAssertEqual(loadedNodes?.count, 3, "Should load all 3 nodes")
        XCTAssertEqual(loadedNodes?[0].id, "1", "First node ID should match")
        XCTAssertEqual(loadedNodes?[0].title, "Task 1", "First node title should match")
        XCTAssertEqual(loadedNodes?[1].nodeType, "note", "Second node type should match")
        XCTAssertEqual(loadedNodes?[2].nodeType, "folder", "Third node type should match")
    }
    
    func testCacheManager_saveAndLoad500PlusNodes_roundTripCorrectly() async throws {
        // Arrange - Create 500+ nodes
        let nodeCount = 550
        let nodes = createLargeNodeSet(count: nodeCount)
        
        // Act - Save
        await cacheManager.saveNodes(nodes)
        
        // Act - Load
        let loadedNodes = await cacheManager.loadNodes()
        
        // Assert
        XCTAssertNotNil(loadedNodes, "Should load nodes")
        XCTAssertEqual(loadedNodes?.count, nodeCount, "Should load all \(nodeCount) nodes")
        
        // Verify sample nodes maintained their data
        if let loaded = loadedNodes {
            // Check first node
            XCTAssertEqual(loaded[0].id, "node-1", "First node ID preserved")
            XCTAssertEqual(loaded[0].title, "Test Node 1", "First node title preserved")
            
            // Check middle node
            let middleIndex = nodeCount / 2
            XCTAssertEqual(loaded[middleIndex].id, "node-\(middleIndex + 1)", "Middle node ID preserved")
            
            // Check last node
            XCTAssertEqual(loaded[nodeCount - 1].id, "node-\(nodeCount)", "Last node ID preserved")
            
            // Verify task data preserved
            let tasks = loaded.filter { $0.nodeType == "task" }
            XCTAssertGreaterThan(tasks.count, 0, "Should have task nodes")
            if let firstTask = tasks.first {
                XCTAssertNotNil(firstTask.taskData, "Task should have task data")
                XCTAssertNotNil(firstTask.taskData?.description, "Task should have description")
            }
            
            // Verify note data preserved
            let notes = loaded.filter { $0.nodeType == "note" }
            XCTAssertGreaterThan(notes.count, 0, "Should have note nodes")
            if let firstNote = notes.first {
                XCTAssertNotNil(firstNote.noteData, "Note should have note data")
            }
        }
    }
    
    func testCacheManager_saveAndLoadNodes_preservesComplexData() async throws {
        // Arrange - Create nodes with complex data
        let complexNode = Node(
            id: "complex-1",
            title: "Complex Task",
            nodeType: "task",
            parentId: "parent-123",
            sortOrder: 5000,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            updatedAt: Date(timeIntervalSince1970: 1700086400),
            isList: true,
            childrenCount: 42,
            tags: [
                Tag(id: "tag-1", name: "urgent", color: "#FF0000", description: nil, createdAt: nil),
                Tag(id: "tag-2", name: "work", color: "#0000FF", description: nil, createdAt: nil)
            ],
            taskData: TaskData(
                description: "A complex task with all fields",
                status: "done",
                priority: "high",
                dueAt: "2025-12-31T23:59:59Z",
                earliestStartAt: "2025-01-01T00:00:00Z",
                completedAt: "2025-06-15T14:30:00Z",
                archived: false
            )
        )
        
        // Act
        await cacheManager.saveNodes([complexNode])
        let loaded = await cacheManager.loadNodes()
        
        // Assert
        XCTAssertEqual(loaded?.count, 1, "Should load one node")
        if let loadedNode = loaded?.first {
            XCTAssertEqual(loadedNode.id, "complex-1")
            XCTAssertEqual(loadedNode.parentId, "parent-123")
            XCTAssertEqual(loadedNode.sortOrder, 5000)
            XCTAssertEqual(loadedNode.isList, true)
            XCTAssertEqual(loadedNode.childrenCount, 42)
            XCTAssertEqual(loadedNode.tags.count, 2)
            XCTAssertEqual(loadedNode.tags[0].name, "urgent")
            XCTAssertEqual(loadedNode.tags[1].color, "#0000FF")
            XCTAssertEqual(loadedNode.taskData?.status, "done")
            XCTAssertEqual(loadedNode.taskData?.priority, "high")
            XCTAssertEqual(loadedNode.taskData?.dueAt, "2025-12-31T23:59:59Z")
            XCTAssertEqual(loadedNode.taskData?.completedAt, "2025-06-15T14:30:00Z")
        }
    }
    
    func testCacheManager_loadNodes_withNoCache_returnsNil() async {
        // Arrange - Ensure cache is empty
        await cacheManager.clearCache()
        
        // Act
        let loaded = await cacheManager.loadNodes()
        
        // Assert
        XCTAssertNil(loaded, "Should return nil when no cache exists")
    }
    
    // MARK: - File Size Tracking Tests
    
    func testCacheManager_getCacheSize_tracksFileSize() async throws {
        // Arrange - Get initial size (should be near 0)
        let initialSize = await cacheManager.getCacheSize()
        
        // Act - Save some nodes
        let nodes = createLargeNodeSet(count: 100)
        await cacheManager.saveNodes(nodes)
        
        // Get size after saving
        let sizeAfterSave = await cacheManager.getCacheSize()
        
        // Assert
        XCTAssertGreaterThan(sizeAfterSave, initialSize, "Cache size should increase after saving")
        XCTAssertGreaterThan(sizeAfterSave, 1000, "100 nodes should be > 1KB")
        
        // Log the size for debugging
        let formattedSize = cacheManager.formatBytes(sizeAfterSave)
        print("Cache size after saving 100 nodes: \(formattedSize)")
    }
    
    func testCacheManager_getCacheSize_with500PlusNodes() async throws {
        // Arrange
        let nodes = createLargeNodeSet(count: 550)
        
        // Act
        await cacheManager.saveNodes(nodes)
        let cacheSize = await cacheManager.getCacheSize()
        
        // Assert
        XCTAssertGreaterThan(cacheSize, 10000, "550 nodes should be > 10KB")
        
        // Log for verification
        let formattedSize = cacheManager.formatBytes(cacheSize)
        print("Cache size for 550 nodes: \(formattedSize)")
        
        // Verify the cache actually contains the data
        let loaded = await cacheManager.loadNodes()
        XCTAssertEqual(loaded?.count, 550, "Should be able to load all nodes back")
    }
    
    func testCacheManager_formatBytes_formatsCorrectly() {
        // Test various sizes - ByteCountFormatter formats differently
        let zero = cacheManager.formatBytes(0)
        XCTAssertTrue(zero.contains("Zero") || zero.contains("0"), "Should format zero correctly")
        
        let kb1 = cacheManager.formatBytes(1024)
        XCTAssertTrue(kb1.contains("1"), "Should format 1KB correctly")
        
        let mb1 = cacheManager.formatBytes(1024 * 1024)
        XCTAssertTrue(mb1.contains("1"), "Should format 1MB correctly")
        
        // Test that it returns a non-empty string for various sizes
        XCTAssertFalse(cacheManager.formatBytes(100 * 1024).isEmpty, "Should format 100KB")
        XCTAssertFalse(cacheManager.formatBytes(10 * 1024 * 1024).isEmpty, "Should format 10MB")
    }
    
    // MARK: - Metadata Persistence Tests
    
    func testCacheManager_saveAndLoadMetadata_persistsCorrectly() async throws {
        // Arrange
        let nodeCount = 42
        let tagCount = 5
        let ruleCount = 3
        
        // Act - Save metadata
        await cacheManager.saveMetadata(
            nodeCount: nodeCount,
            tagCount: tagCount,
            ruleCount: ruleCount
        )
        
        // Act - Load metadata
        let loaded = await cacheManager.loadMetadata()
        
        // Assert
        XCTAssertNotNil(loaded, "Should load metadata")
        XCTAssertEqual(loaded?.nodeCount, nodeCount, "Node count should match")
        XCTAssertEqual(loaded?.tagCount, tagCount, "Tag count should match")
        XCTAssertEqual(loaded?.ruleCount, ruleCount, "Rule count should match")
        
        // Check sync date is recent
        if let syncDate = loaded?.lastSyncDate {
            let timeDiff = abs(syncDate.timeIntervalSinceNow)
            XCTAssertLessThan(timeDiff, 5, "Sync date should be within 5 seconds")
        }
    }
    
    func testCacheManager_loadMetadata_withNoCache_returnsNil() async {
        // Arrange - Clear cache
        await cacheManager.clearCache()
        
        // Act
        let loaded = await cacheManager.loadMetadata()
        
        // Assert
        XCTAssertNil(loaded, "Should return nil when no metadata exists")
    }
    
    func testCacheManager_metadataUserId_persistsFromUserDefaults() async throws {
        // Arrange - Set a user ID in UserDefaults
        let testUserId = "test-user-123"
        UserDefaults.standard.set(testUserId, forKey: "user_id")
        
        // Act - Save and load metadata
        await cacheManager.saveMetadata(nodeCount: 10, tagCount: 2, ruleCount: 1)
        let loaded = await cacheManager.loadMetadata()
        
        // Assert
        XCTAssertEqual(loaded?.userId, testUserId, "User ID should be preserved")
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "user_id")
    }
    
    // MARK: - Clear Cache Tests
    
    func testCacheManager_clearCache_removesAllData() async throws {
        // Arrange - Save some data
        let nodes = createLargeNodeSet(count: 50)
        await cacheManager.saveNodes(nodes)
        await cacheManager.saveMetadata(nodeCount: 50, tagCount: 5, ruleCount: 2)
        
        // Verify data exists
        let nodesExist = await cacheManager.loadNodes()
        let metadataExists = await cacheManager.loadMetadata()
        XCTAssertNotNil(nodesExist, "Nodes should exist before clear")
        XCTAssertNotNil(metadataExists, "Metadata should exist before clear")
        
        // Act - Clear cache
        await cacheManager.clearCache()
        
        // Assert - All data removed
        let nodesAfterClear = await cacheManager.loadNodes()
        let metadataAfterClear = await cacheManager.loadMetadata()
        XCTAssertNil(nodesAfterClear, "Nodes should be nil after clear")
        XCTAssertNil(metadataAfterClear, "Metadata should be nil after clear")
        
        let size = await cacheManager.getCacheSize()
        XCTAssertEqual(size, 0, "Cache size should be 0 after clear")
    }
    
    // MARK: - Performance Tests
    
    func testCacheManager_performance_save1000Nodes() async throws {
        // Arrange
        let nodes = createLargeNodeSet(count: 1000)
        
        // Act & Measure
        let startTime = Date()
        await cacheManager.saveNodes(nodes)
        let saveTime = Date().timeIntervalSince(startTime)
        
        // Assert
        XCTAssertLessThan(saveTime, 2.0, "Should save 1000 nodes in less than 2 seconds")
        
        // Verify saved correctly
        let loaded = await cacheManager.loadNodes()
        XCTAssertEqual(loaded?.count, 1000, "Should load all 1000 nodes")
    }
    
    func testCacheManager_performance_load1000Nodes() async throws {
        // Arrange - Save 1000 nodes first
        let nodes = createLargeNodeSet(count: 1000)
        await cacheManager.saveNodes(nodes)
        
        // Act & Measure
        let startTime = Date()
        let loaded = await cacheManager.loadNodes()
        let loadTime = Date().timeIntervalSince(startTime)
        
        // Assert
        XCTAssertLessThan(loadTime, 1.0, "Should load 1000 nodes in less than 1 second")
        XCTAssertEqual(loaded?.count, 1000, "Should load all nodes")
    }
}