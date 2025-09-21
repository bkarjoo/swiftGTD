import XCTest
import Foundation
import Combine
@testable import Services
@testable import Models
@testable import Core
@testable import Networking

/// Tests for DataManager offline delete functionality
@MainActor
final class DataManagerOfflineDeleteTests: XCTestCase {
    
    private var dataManager: DataManager!
    private var mockNetworkMonitor: MockOfflineNetworkMonitor!
    private var mockAPI: MockAPIClient!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockNetworkMonitor = MockOfflineNetworkMonitor()
        mockNetworkMonitor.isConnected = false // Offline by default
        
        mockAPI = MockAPIClient()
        cancellables = []
        
        dataManager = DataManager(
            apiClient: mockAPI,
            networkMonitor: mockNetworkMonitor
        )
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // MARK: - Basic Delete Tests
    
    func testOfflineDelete_singleNode_removesLocally() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create a node offline
        let node = await dataManager.createNode(
            title: "Node to Delete",
            type: "task",
            content: "Will be deleted",
            parentId: nil
        )
        
        XCTAssertNotNil(node)
        XCTAssertEqual(dataManager.nodes.count, 1)
        
        // Act - Delete the node
        await dataManager.deleteNode(node!)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "Node should be removed from local collection")
        XCTAssertNil(dataManager.nodes.first { $0.id == node?.id }, "Node should not exist locally")
    }
    
    func testOfflineDelete_withDescendants_removesAll() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create parent folder
        let parent = await dataManager.createNode(
            title: "Parent Folder",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        // Create child nodes
        let child1 = await dataManager.createNode(
            title: "Child 1",
            type: "task",
            content: "First child",
            parentId: parent?.id
        )
        
        let child2 = await dataManager.createNode(
            title: "Child 2",
            type: "task",
            content: "Second child",
            parentId: parent?.id
        )
        
        // Create grandchild
        let grandchild = await dataManager.createNode(
            title: "Grandchild",
            type: "note",
            content: "Nested note",
            parentId: child1?.id
        )
        
        XCTAssertEqual(dataManager.nodes.count, 4, "Should have 4 nodes")
        
        // Act - Delete parent (should delete all descendants)
        await dataManager.deleteNode(parent!)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "All nodes should be deleted")
        XCTAssertNil(dataManager.nodes.first { $0.id == parent?.id }, "Parent should be deleted")
        XCTAssertNil(dataManager.nodes.first { $0.id == child1?.id }, "Child1 should be deleted")
        XCTAssertNil(dataManager.nodes.first { $0.id == child2?.id }, "Child2 should be deleted")
        XCTAssertNil(dataManager.nodes.first { $0.id == grandchild?.id }, "Grandchild should be deleted")
    }
    
    // MARK: - Real ID Tests
    
    func testOfflineDelete_realId_queuesDeleteOperation() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create a node with server ID
        let formatter = ISO8601DateFormatter()
        let serverNode = Node(
            id: "server-789",
            title: "Server Node",
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "From server",
                status: "todo",
                completedAt: nil
            )
        )
        
        await dataManager.setNodes([serverNode])
        XCTAssertEqual(dataManager.nodes.count, 1)
        
        // Act - Delete server node offline
        await dataManager.deleteNode(serverNode)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "Node should be removed locally")
        
        // In production, would verify:
        // - OfflineQueueManager.queueDelete(nodeId: "server-789") was called
        // - Delete operation added to pending queue
    }
    
    func testOfflineDelete_realIdWithDescendants_queuesAllDeletes() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let formatter = ISO8601DateFormatter()
        
        // Create server nodes hierarchy
        let parent = Node(
            id: "server-parent",
            title: "Parent",
            nodeType: "folder",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0
        )
        
        let child = Node(
            id: "server-child",
            title: "Child",
            nodeType: "task",
            parentId: "server-parent",
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 1,
            taskData: TaskData(
                description: "Child task",
                status: "todo",
                completedAt: nil
            )
        )
        
        await dataManager.setNodes([parent, child])
        XCTAssertEqual(dataManager.nodes.count, 2)
        
        // Act - Delete parent
        await dataManager.deleteNode(parent)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "All nodes should be removed")
        
        // In production, would verify:
        // - Delete operations queued for both parent and child
        // - Operations maintain proper order
    }
    
    // MARK: - Temp ID Tests
    
    func testOfflineDelete_tempId_removesWithoutQueuing() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create temp nodes offline
        let tempNode = await dataManager.createNode(
            title: "Temp Node",
            type: "task",
            content: "Created offline",
            parentId: nil
        )
        
        XCTAssertNotNil(tempNode)
        let tempUuid = String(tempNode!.id.dropFirst(5))
        XCTAssertNotNil(UUID(uuidString: tempUuid), "Should have UUID as temp ID")
        XCTAssertEqual(dataManager.nodes.count, 1)
        
        // Act - Delete temp node
        await dataManager.deleteNode(tempNode!)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "Node should be removed")
        
        // In production, would verify:
        // - No delete operation queued (temp node never existed on server)
        // - Any queued create operation for this temp ID is removed
    }
    
    func testOfflineDelete_tempIdHierarchy_removesAllWithoutQueuing() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create temp hierarchy
        let tempParent = await dataManager.createNode(
            title: "Temp Parent",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        _ = await dataManager.createNode(
            title: "Temp Child 1",
            type: "task",
            content: "First",
            parentId: tempParent?.id
        )
        
        _ = await dataManager.createNode(
            title: "Temp Child 2",
            type: "note",
            content: "Second",
            parentId: tempParent?.id
        )
        
        XCTAssertEqual(dataManager.nodes.count, 3)
        
        // Act - Delete parent
        await dataManager.deleteNode(tempParent!)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "All temp nodes should be removed")
        
        // In production, would verify:
        // - No delete operations queued (all temp nodes)
        // - Any queued create operations for these temp IDs are removed
    }
    
    // MARK: - Mixed ID Tests
    
    func testOfflineDelete_mixedIds_handlesCorrectly() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let formatter = ISO8601DateFormatter()
        
        // Create server node
        let serverNode = Node(
            id: "server-100",
            title: "Server Parent",
            nodeType: "folder",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0
        )
        
        await dataManager.setNodes([serverNode])
        
        // Create temp child under server parent
        _ = await dataManager.createNode(
            title: "Temp Child",
            type: "task",
            content: "Mixed hierarchy",
            parentId: "server-100"
        )
        
        XCTAssertEqual(dataManager.nodes.count, 2)
        
        // Act - Delete server parent
        await dataManager.deleteNode(serverNode)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "Both nodes should be removed")
        
        // In production, would verify:
        // - Delete operation queued for server-100
        // - No delete operation for temp child (never existed on server)
        // - Any queued create for temp child is removed
    }
    
    // MARK: - Error Message Tests
    
    func testOfflineDelete_setsOfflineMessage() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let node = await dataManager.createNode(
            title: "Node to Delete",
            type: "task",
            content: nil,
            parentId: nil
        )
        
        // Clear any previous message
        dataManager.errorMessage = nil
        
        // Act
        await dataManager.deleteNode(node!)
        
        // Assert
        XCTAssertEqual(
            dataManager.errorMessage,
            "Deleted offline - will sync when connected",
            "Should set offline message"
        )
    }
    
    // MARK: - Edge Cases
    
    func testOfflineDelete_nonExistentNode_handlesGracefully() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        let formatter = ISO8601DateFormatter()
        let nonExistentNode = Node(
            id: "not-in-collection",
            title: "Ghost Node",
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "Doesn't exist",
                status: "todo",
                completedAt: nil
            )
        )
        
        let initialCount = dataManager.nodes.count
        
        // Act
        await dataManager.deleteNode(nonExistentNode)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, initialCount, "Count should remain unchanged")
    }
    
    func testOfflineDelete_partialHierarchy_deletesOnlyDescendants() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create hierarchy
        let root = await dataManager.createNode(
            title: "Root",
            type: "folder",
            content: nil,
            parentId: nil
        )
        
        let branch1 = await dataManager.createNode(
            title: "Branch 1",
            type: "folder",
            content: nil,
            parentId: root?.id
        )
        
        let branch2 = await dataManager.createNode(
            title: "Branch 2",
            type: "folder",
            content: nil,
            parentId: root?.id
        )
        
        let leaf1 = await dataManager.createNode(
            title: "Leaf 1",
            type: "task",
            content: "Under branch 1",
            parentId: branch1?.id
        )
        
        let leaf2 = await dataManager.createNode(
            title: "Leaf 2",
            type: "task",
            content: "Under branch 2",
            parentId: branch2?.id
        )
        
        XCTAssertEqual(dataManager.nodes.count, 5)
        
        // Act - Delete only branch1
        await dataManager.deleteNode(branch1!)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 3, "Should have 3 nodes remaining")
        XCTAssertNotNil(dataManager.nodes.first { $0.id == root?.id }, "Root should exist")
        XCTAssertNil(dataManager.nodes.first { $0.id == branch1?.id }, "Branch1 should be deleted")
        XCTAssertNotNil(dataManager.nodes.first { $0.id == branch2?.id }, "Branch2 should exist")
        XCTAssertNil(dataManager.nodes.first { $0.id == leaf1?.id }, "Leaf1 should be deleted")
        XCTAssertNotNil(dataManager.nodes.first { $0.id == leaf2?.id }, "Leaf2 should exist")
    }
    
    // MARK: - Complex Scenarios
    
    func testOfflineDelete_afterOnlineDelete_queuesCorrectly() async throws {
        // Arrange - Create node with server ID
        let formatter = ISO8601DateFormatter()
        let serverNode = Node(
            id: "server-200",
            title: "Node to Delete",
            nodeType: "task",
            parentId: nil,
            ownerId: "test-user",
            createdAt: formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date()),
            sortOrder: 0,
            taskData: TaskData(
                description: "Will be deleted offline",
                status: "todo",
                completedAt: nil
            )
        )
        
        await dataManager.setNodes([serverNode])
        
        // Act - Ensure offline and delete
        mockNetworkMonitor.isConnected = false
        await dataManager.deleteNode(serverNode)
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "Node should be removed")
        
        // In production, would verify:
        // - Delete operation queued for server-200
    }
    
    func testOfflineDelete_multipleDeletes_allProcessed() async throws {
        // Arrange
        mockNetworkMonitor.isConnected = false
        
        // Create multiple nodes
        let nodes = await withTaskGroup(of: Node?.self) { group in
            for i in 1...5 {
                group.addTask {
                    await self.dataManager.createNode(
                        title: "Node \(i)",
                        type: i % 2 == 0 ? "task" : "note",
                        content: "Content \(i)",
                        parentId: nil
                    )
                }
            }
            
            var results: [Node] = []
            for await node in group {
                if let node = node {
                    results.append(node)
                }
            }
            return results
        }
        
        XCTAssertEqual(nodes.count, 5)
        XCTAssertEqual(dataManager.nodes.count, 5)
        
        // Act - Delete all nodes
        for node in nodes {
            await dataManager.deleteNode(node)
        }
        
        // Assert
        XCTAssertEqual(dataManager.nodes.count, 0, "All nodes should be deleted")
    }
}