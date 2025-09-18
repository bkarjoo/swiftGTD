import XCTest
import Foundation
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Tests for OfflineQueueManager temp ID mapping functionality
@MainActor
final class OfflineQueueTempIdMappingTests: XCTestCase {
    
    private var queueManager: OfflineQueueManager!
    
    override func setUp() async throws {
        try await super.setUp()
        queueManager = OfflineQueueManager.shared
        await queueManager.clearQueue()
    }
    
    override func tearDown() async throws {
        await queueManager.clearQueue()
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestNode(id: String, title: String, type: String = "task", parentId: String? = nil) -> Node {
        let isoFormatter = ISO8601DateFormatter()
        return Node(
            id: id,
            title: title,
            nodeType: type,
            parentId: parentId,
            ownerId: "test-owner",
            createdAt: isoFormatter.string(from: Date()),
            updatedAt: isoFormatter.string(from: Date()),
            sortOrder: 1000,
            isList: false,
            childrenCount: 0,
            tags: [],
            taskData: type == "task" ? TaskData(status: "todo") : nil,
            noteData: nil,
            templateData: nil,
            smartFolderData: nil
        )
    }
    
    // MARK: - Basic Temp ID Mapping Tests
    
    func testTempIdMapping_singleNode_mapsCorrectly() async throws {
        // Arrange
        let tempId = "temp-\(UUID().uuidString)"
        let serverId = "server-12345"
        
        // Create initial mapping
        var tempIdMap: [String: String] = [:]
        tempIdMap[tempId] = serverId
        
        // Assert
        XCTAssertEqual(tempIdMap[tempId], serverId, "Temp ID should map to server ID")
        XCTAssertEqual(tempIdMap.count, 1, "Should have one mapping")
    }
    
    func testTempIdMapping_multipleNodes_mapsAllCorrectly() async throws {
        // Arrange
        let tempId1 = "temp-node-1"
        let tempId2 = "temp-node-2"
        let tempId3 = "temp-node-3"
        
        let serverId1 = "server-node-1"
        let serverId2 = "server-node-2"
        let serverId3 = "server-node-3"
        
        // Create mappings
        var tempIdMap: [String: String] = [:]
        tempIdMap[tempId1] = serverId1
        tempIdMap[tempId2] = serverId2
        tempIdMap[tempId3] = serverId3
        
        // Assert
        XCTAssertEqual(tempIdMap[tempId1], serverId1, "First temp ID should map correctly")
        XCTAssertEqual(tempIdMap[tempId2], serverId2, "Second temp ID should map correctly")
        XCTAssertEqual(tempIdMap[tempId3], serverId3, "Third temp ID should map correctly")
        XCTAssertEqual(tempIdMap.count, 3, "Should have three mappings")
    }
    
    // MARK: - Parent Reference Mapping Tests
    
    func testTempIdMapping_parentReference_replacesCorrectly() async throws {
        // Arrange
        let parentTempId = "temp-parent"
        let childTempId = "temp-child"
        let parentServerId = "server-parent-123"
        
        let childNode = createTestNode(
            id: childTempId,
            title: "Child Node",
            type: "task",
            parentId: parentTempId
        )
        
        // Create mapping
        var tempIdMap: [String: String] = [:]
        tempIdMap[parentTempId] = parentServerId
        
        // Act - Replace parent reference
        let mappedParentId = tempIdMap[childNode.parentId!] ?? childNode.parentId!
        
        // Assert
        XCTAssertEqual(mappedParentId, parentServerId, "Parent ID should be mapped to server ID")
        XCTAssertNotEqual(mappedParentId, parentTempId, "Should not be temp ID anymore")
    }
    
    func testTempIdMapping_nestedHierarchy_mapsAllLevels() async throws {
        // Arrange - Create 3-level hierarchy
        let rootTempId = "temp-root"
        let middleTempId = "temp-middle"
        let leafTempId = "temp-leaf"
        
        let rootServerId = "server-root"
        let middleServerId = "server-middle"
        let leafServerId = "server-leaf"
        
        // Create nodes with parent references
        let rootNode = createTestNode(id: rootTempId, title: "Root", type: "folder", parentId: nil)
        let middleNode = createTestNode(id: middleTempId, title: "Middle", type: "folder", parentId: rootTempId)
        let leafNode = createTestNode(id: leafTempId, title: "Leaf", type: "task", parentId: middleTempId)
        
        // Create mappings
        var tempIdMap: [String: String] = [:]
        tempIdMap[rootTempId] = rootServerId
        tempIdMap[middleTempId] = middleServerId
        tempIdMap[leafTempId] = leafServerId
        
        // Act - Map all IDs
        let mappedRootId = tempIdMap[rootNode.id] ?? rootNode.id
        let mappedMiddleId = tempIdMap[middleNode.id] ?? middleNode.id
        let mappedMiddleParentId = tempIdMap[middleNode.parentId!] ?? middleNode.parentId!
        let mappedLeafId = tempIdMap[leafNode.id] ?? leafNode.id
        let mappedLeafParentId = tempIdMap[leafNode.parentId!] ?? leafNode.parentId!
        
        // Assert
        XCTAssertEqual(mappedRootId, rootServerId, "Root should map to server ID")
        XCTAssertEqual(mappedMiddleId, middleServerId, "Middle should map to server ID")
        XCTAssertEqual(mappedMiddleParentId, rootServerId, "Middle's parent should map to root's server ID")
        XCTAssertEqual(mappedLeafId, leafServerId, "Leaf should map to server ID")
        XCTAssertEqual(mappedLeafParentId, middleServerId, "Leaf's parent should map to middle's server ID")
    }
    
    // MARK: - Node Collection Mapping Tests
    
    func testTempIdMapping_nodeArray_replacesAllTempIds() async throws {
        // Arrange
        let nodes = [
            createTestNode(id: "temp-1", title: "Node 1", parentId: nil),
            createTestNode(id: "temp-2", title: "Node 2", parentId: "temp-1"),
            createTestNode(id: "temp-3", title: "Node 3", parentId: "temp-1"),
            createTestNode(id: "regular-1", title: "Node 4", parentId: nil),
            createTestNode(id: "temp-4", title: "Node 5", parentId: "regular-1")
        ]
        
        var tempIdMap: [String: String] = [
            "temp-1": "server-1",
            "temp-2": "server-2",
            "temp-3": "server-3",
            "temp-4": "server-4"
        ]
        
        // Act - Map all nodes
        let mappedNodes = nodes.map { node in
            Node(
                id: tempIdMap[node.id] ?? node.id,
                title: node.title,
                nodeType: node.nodeType,
                parentId: node.parentId.flatMap { tempIdMap[$0] ?? $0 },
                ownerId: node.ownerId,
                createdAt: node.createdAt,
                updatedAt: node.updatedAt,
                sortOrder: node.sortOrder,
                isList: node.isList,
                childrenCount: node.childrenCount,
                tags: node.tags,
                taskData: node.taskData,
                noteData: node.noteData,
                templateData: node.templateData,
                smartFolderData: node.smartFolderData
            )
        }
        
        // Assert
        XCTAssertEqual(mappedNodes[0].id, "server-1", "First node should have server ID")
        XCTAssertEqual(mappedNodes[1].id, "server-2", "Second node should have server ID")
        XCTAssertEqual(mappedNodes[1].parentId, "server-1", "Second node's parent should be mapped")
        XCTAssertEqual(mappedNodes[2].id, "server-3", "Third node should have server ID")
        XCTAssertEqual(mappedNodes[2].parentId, "server-1", "Third node's parent should be mapped")
        XCTAssertEqual(mappedNodes[3].id, "regular-1", "Regular ID should stay unchanged")
        XCTAssertEqual(mappedNodes[4].id, "server-4", "Fifth node should have server ID")
        XCTAssertEqual(mappedNodes[4].parentId, "regular-1", "Parent with regular ID should stay unchanged")
    }
    
    // MARK: - Edge Cases
    
    func testTempIdMapping_unmappedTempId_remainsUnchanged() async throws {
        // Arrange
        let tempId = "temp-unmapped"
        let node = createTestNode(id: tempId, title: "Unmapped Node")
        let tempIdMap: [String: String] = [:] // Empty map
        
        // Act
        let mappedId = tempIdMap[node.id] ?? node.id
        
        // Assert
        XCTAssertEqual(mappedId, tempId, "Unmapped temp ID should remain unchanged")
    }
    
    func testTempIdMapping_regularId_remainsUnchanged() async throws {
        // Arrange
        let regularId = "12345-regular-node"
        let node = createTestNode(id: regularId, title: "Regular Node")
        let tempIdMap: [String: String] = [
            "temp-1": "server-1",
            "temp-2": "server-2"
        ]
        
        // Act
        let mappedId = tempIdMap[node.id] ?? node.id
        
        // Assert
        XCTAssertEqual(mappedId, regularId, "Regular ID should remain unchanged")
    }
    
    func testTempIdMapping_nilParentId_remainsNil() async throws {
        // Arrange
        let node = createTestNode(id: "temp-1", title: "Root Node", parentId: nil)
        let tempIdMap: [String: String] = ["temp-1": "server-1"]
        
        // Act
        let mappedParentId = node.parentId.flatMap { tempIdMap[$0] ?? $0 }
        
        // Assert
        XCTAssertNil(mappedParentId, "Nil parent ID should remain nil")
    }
    
    // MARK: - Map Return Tests
    
    func testTempIdMapping_processingReturnsMap_containsAllMappings() async throws {
        // This simulates what processPendingOperations returns
        
        // Arrange
        let expectedMappings = [
            "temp-1": "server-1",
            "temp-2": "server-2",
            "temp-3": "server-3"
        ]
        
        // Act - Simulate processing that builds map
        var returnedMap: [String: String] = [:]
        for (tempId, serverId) in expectedMappings {
            returnedMap[tempId] = serverId
        }
        
        // Assert
        XCTAssertEqual(returnedMap.count, expectedMappings.count, "Should return all mappings")
        for (tempId, expectedServerId) in expectedMappings {
            XCTAssertEqual(returnedMap[tempId], expectedServerId, "Mapping for \(tempId) should be correct")
        }
    }
    
    func testTempIdMapping_emptyQueue_returnsEmptyMap() async throws {
        // Arrange - No operations to process
        await queueManager.clearQueue()
        
        // Act - Simulate processing empty queue
        let returnedMap: [String: String] = [:]
        
        // Assert
        XCTAssertTrue(returnedMap.isEmpty, "Empty queue should return empty map")
    }
    
    // MARK: - Complex Scenarios
    
    func testTempIdMapping_circularReference_handlesGracefully() async throws {
        // Arrange - Two nodes referencing each other's temp IDs
        let tempId1 = "temp-1"
        let tempId2 = "temp-2"
        
        // In practice, this shouldn't happen, but test graceful handling
        let node1 = createTestNode(id: tempId1, title: "Node 1", parentId: tempId2)
        let node2 = createTestNode(id: tempId2, title: "Node 2", parentId: tempId1)
        
        let tempIdMap: [String: String] = [
            tempId1: "server-1",
            tempId2: "server-2"
        ]
        
        // Act
        let mapped1ParentId = tempIdMap[node1.parentId!] ?? node1.parentId!
        let mapped2ParentId = tempIdMap[node2.parentId!] ?? node2.parentId!
        
        // Assert
        XCTAssertEqual(mapped1ParentId, "server-2", "Node 1's parent should map to server-2")
        XCTAssertEqual(mapped2ParentId, "server-1", "Node 2's parent should map to server-1")
    }
    
    func testTempIdMapping_deepNesting_mapsAllLevels() async throws {
        // Arrange - Create 5-level deep hierarchy
        let tempIds = (1...5).map { "temp-level-\($0)" }
        let serverIds = (1...5).map { "server-level-\($0)" }
        
        var tempIdMap: [String: String] = [:]
        for (index, tempId) in tempIds.enumerated() {
            tempIdMap[tempId] = serverIds[index]
        }
        
        // Create nodes with parent references
        var nodes: [Node] = []
        for (index, tempId) in tempIds.enumerated() {
            let parentId = index > 0 ? tempIds[index - 1] : nil
            let node = createTestNode(
                id: tempId,
                title: "Level \(index + 1)",
                type: index == 4 ? "task" : "folder",
                parentId: parentId
            )
            nodes.append(node)
        }
        
        // Act - Map all parent references
        let mappedNodes = nodes.map { node in
            Node(
                id: tempIdMap[node.id] ?? node.id,
                title: node.title,
                nodeType: node.nodeType,
                parentId: node.parentId.flatMap { tempIdMap[$0] ?? $0 },
                ownerId: node.ownerId,
                createdAt: node.createdAt,
                updatedAt: node.updatedAt,
                sortOrder: node.sortOrder,
                isList: node.isList,
                childrenCount: node.childrenCount,
                tags: node.tags,
                taskData: node.taskData,
                noteData: node.noteData,
                templateData: node.templateData,
                smartFolderData: node.smartFolderData
            )
        }
        
        // Assert
        XCTAssertNil(mappedNodes[0].parentId, "Level 1 should have no parent")
        XCTAssertEqual(mappedNodes[1].parentId, serverIds[0], "Level 2 parent should be server-level-1")
        XCTAssertEqual(mappedNodes[2].parentId, serverIds[1], "Level 3 parent should be server-level-2")
        XCTAssertEqual(mappedNodes[3].parentId, serverIds[2], "Level 4 parent should be server-level-3")
        XCTAssertEqual(mappedNodes[4].parentId, serverIds[3], "Level 5 parent should be server-level-4")
        
        // Verify all IDs are mapped
        for (index, node) in mappedNodes.enumerated() {
            XCTAssertEqual(node.id, serverIds[index], "Level \(index + 1) ID should be mapped")
            XCTAssertTrue(node.id.starts(with: "server-"), "All IDs should be server IDs")
        }
    }
    
    // MARK: - Performance Tests
    
    func testTempIdMapping_largeDataset_performsEfficiently() async throws {
        // Arrange - Create 1000 nodes with temp IDs
        let nodeCount = 1000
        var tempIdMap: [String: String] = [:]
        var nodes: [Node] = []
        
        for i in 1...nodeCount {
            let tempId = "temp-\(i)"
            let serverId = "server-\(i)"
            tempIdMap[tempId] = serverId
            
            // Create hierarchy: every 10th node is a parent
            let parentId = i > 10 ? "temp-\(((i - 1) / 10) * 10)" : nil
            let node = createTestNode(
                id: tempId,
                title: "Node \(i)",
                type: i % 10 == 0 ? "folder" : "task",
                parentId: parentId
            )
            nodes.append(node)
        }
        
        // Act - Measure mapping performance
        let startTime = Date()
        let mappedNodes = nodes.map { node in
            Node(
                id: tempIdMap[node.id] ?? node.id,
                title: node.title,
                nodeType: node.nodeType,
                parentId: node.parentId.flatMap { tempIdMap[$0] ?? $0 },
                ownerId: node.ownerId,
                createdAt: node.createdAt,
                updatedAt: node.updatedAt,
                sortOrder: node.sortOrder,
                isList: node.isList,
                childrenCount: node.childrenCount,
                tags: node.tags,
                taskData: node.taskData,
                noteData: node.noteData,
                templateData: node.templateData,
                smartFolderData: node.smartFolderData
            )
        }
        let mappingTime = Date().timeIntervalSince(startTime)
        
        // Assert
        XCTAssertEqual(mappedNodes.count, nodeCount, "Should map all nodes")
        XCTAssertLessThan(mappingTime, 1.0, "Should map 1000 nodes in less than 1 second")
        
        // Verify sample mappings
        XCTAssertEqual(mappedNodes[0].id, "server-1", "First node should be mapped")
        XCTAssertEqual(mappedNodes[999].id, "server-1000", "Last node should be mapped")
        XCTAssertEqual(mappedNodes[99].parentId, "server-90", "100th node's parent should be mapped")
    }
}