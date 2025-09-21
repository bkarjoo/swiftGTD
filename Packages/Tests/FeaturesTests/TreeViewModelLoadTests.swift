import XCTest
import Foundation
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Networking
@testable import Core

/// Mock DataManager for testing TreeViewModel
@MainActor
class MockDataManager: DataManager {
    var mockNodes: [Node] = []
    var syncAllDataCalled = false
    var syncCallCount = 0
    
    override init(
        apiClient: APIClientProtocol = APIClient.shared,
        networkMonitor: NetworkMonitorProtocol? = nil
    ) {
        super.init(apiClient: apiClient, networkMonitor: networkMonitor)
    }
    
    override func syncAllData() async {
        syncAllDataCalled = true
        syncCallCount += 1
        // Set nodes to trigger the publisher
        self.nodes = mockNodes
    }
}

/// Tests for TreeViewModel loading via DataManager
@MainActor
final class TreeViewModelLoadTests: XCTestCase {
    
    // MARK: - Load and Build Tests
    
    func testTreeViewModel_loadAllNodes_viaDataManager_buildsNodeChildrenAndSorts() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()
        
        // Create test nodes with parent-child relationships
        let rootNode1 = Node(
            id: "root-1",
            title: "Root 1",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 2000,
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date()
        )
        
        let rootNode2 = Node(
            id: "root-2",
            title: "Root 2",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date().addingTimeInterval(-7200),
            updatedAt: Date()
        )
        
        let childNode1 = Node(
            id: "child-1",
            title: "Child 1",
            nodeType: "task",
            parentId: "root-1",
            sortOrder: 3000,
            createdAt: Date().addingTimeInterval(-1800),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let childNode2 = Node(
            id: "child-2",
            title: "Child 2",
            nodeType: "task",
            parentId: "root-1",
            sortOrder: 1500,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        let nestedChild = Node(
            id: "nested-1",
            title: "Nested Child",
            nodeType: "note",
            parentId: "child-2",
            sortOrder: 1000,
            createdAt: Date().addingTimeInterval(-900),
            updatedAt: Date(),
            noteData: NoteData(body: "Test note")
        )
        
        mockDataManager.mockNodes = [rootNode1, rootNode2, childNode1, childNode2, nestedChild]
        
        // Set up the DataManager
        treeViewModel.setDataManager(mockDataManager)
        
        // Act
        await treeViewModel.initialLoad()
        
        // Assert - Verify DataManager was called
        XCTAssertTrue(mockDataManager.syncAllDataCalled, "Should call syncAllData on DataManager")
        XCTAssertEqual(mockDataManager.syncCallCount, 1, "Should call syncAllData once")
        
        // Assert - Verify allNodes populated
        XCTAssertEqual(treeViewModel.allNodes.count, 5, "Should have all 5 nodes")
        XCTAssertEqual(treeViewModel.allNodes.map { $0.id }.sorted(), 
                      ["child-1", "child-2", "nested-1", "root-1", "root-2"], 
                      "All nodes should be present")
        
        // Assert - Verify root nodes are sorted by sortOrder
        let rootNodes = treeViewModel.getRootNodes()
        XCTAssertEqual(rootNodes.count, 2, "Should have 2 root nodes")
        XCTAssertEqual(rootNodes[0].id, "root-2", "First root should be root-2 (sortOrder 1000)")
        XCTAssertEqual(rootNodes[1].id, "root-1", "Second root should be root-1 (sortOrder 2000)")
        
        // Assert - Verify nodeChildren mapping
        XCTAssertNotNil(treeViewModel.nodeChildren["root-1"], "Should have children for root-1")
        XCTAssertEqual(treeViewModel.nodeChildren["root-1"]?.count, 2, "root-1 should have 2 children")
        
        // Assert - Verify children are sorted by sortOrder
        let root1Children = treeViewModel.getChildren(of: "root-1")
        XCTAssertEqual(root1Children.count, 2, "Should have 2 children for root-1")
        XCTAssertEqual(root1Children[0].id, "child-2", "First child should be child-2 (sortOrder 1500)")
        XCTAssertEqual(root1Children[1].id, "child-1", "Second child should be child-1 (sortOrder 3000)")
        
        // Assert - Verify nested children
        XCTAssertNotNil(treeViewModel.nodeChildren["child-2"], "Should have children for child-2")
        XCTAssertEqual(treeViewModel.nodeChildren["child-2"]?.count, 1, "child-2 should have 1 child")
        XCTAssertEqual(treeViewModel.nodeChildren["child-2"]?[0].id, "nested-1", "Nested child should be present")
        
        // Assert - Verify empty parent has no entry
        XCTAssertNil(treeViewModel.nodeChildren["root-2"], "root-2 should not have children entry")
        XCTAssertNil(treeViewModel.nodeChildren["child-1"], "child-1 should not have children entry")
        
        // Assert - Loading state
        XCTAssertFalse(treeViewModel.isLoading, "Loading should be complete")
    }
    
    func testTreeViewModel_loadAllNodes_withEmptyDataManager_handlesGracefully() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()
        mockDataManager.mockNodes = []
        
        treeViewModel.setDataManager(mockDataManager)
        
        // Act
        await treeViewModel.initialLoad()
        
        // Assert
        XCTAssertTrue(mockDataManager.syncAllDataCalled, "Should call syncAllData")
        XCTAssertEqual(treeViewModel.allNodes.count, 0, "Should have no nodes")
        XCTAssertEqual(treeViewModel.nodeChildren.count, 0, "Should have no children mappings")
        XCTAssertEqual(treeViewModel.getRootNodes().count, 0, "Should have no root nodes")
        XCTAssertFalse(treeViewModel.isLoading, "Loading should be complete")
    }
    
    func testTreeViewModel_loadAllNodes_withComplexHierarchy_buildsCorrectly() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()
        
        // Create a complex hierarchy: Project -> Area -> Tasks
        let project = Node(
            id: "proj-1",
            title: "Project Alpha",
            nodeType: "project",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date()
        )
        
        let area1 = Node(
            id: "area-1",
            title: "Frontend",
            nodeType: "area",
            parentId: "proj-1",
            sortOrder: 1000,
            createdAt: Date().addingTimeInterval(-72000),
            updatedAt: Date()
        )
        
        let area2 = Node(
            id: "area-2",
            title: "Backend",
            nodeType: "area",
            parentId: "proj-1",
            sortOrder: 2000,
            createdAt: Date().addingTimeInterval(-72000),
            updatedAt: Date()
        )
        
        // Tasks under Frontend
        let task1 = Node(
            id: "task-1",
            title: "Design UI",
            nodeType: "task",
            parentId: "area-1",
            sortOrder: 100,
            createdAt: Date().addingTimeInterval(-36000),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "high")
        )
        
        let task2 = Node(
            id: "task-2",
            title: "Implement Components",
            nodeType: "task",
            parentId: "area-1",
            sortOrder: 200,
            createdAt: Date().addingTimeInterval(-36000),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        // Tasks under Backend
        let task3 = Node(
            id: "task-3",
            title: "Setup Database",
            nodeType: "task",
            parentId: "area-2",
            sortOrder: 50,
            createdAt: Date().addingTimeInterval(-36000),
            updatedAt: Date(),
            taskData: TaskData(status: "done", priority: "critical", completedAt: "2025-09-16T10:00:00Z")
        )
        
        mockDataManager.mockNodes = [project, area1, area2, task1, task2, task3]
        treeViewModel.setDataManager(mockDataManager)
        
        // Act
        await treeViewModel.initialLoad()
        
        // Assert - Hierarchy
        let rootNodes = treeViewModel.getRootNodes()
        XCTAssertEqual(rootNodes.count, 1, "Should have 1 root (project)")
        XCTAssertEqual(rootNodes[0].id, "proj-1")
        
        let projectChildren = treeViewModel.getChildren(of: "proj-1")
        XCTAssertEqual(projectChildren.count, 2, "Project should have 2 areas")
        XCTAssertEqual(projectChildren[0].id, "area-1", "Frontend first (sortOrder 1000)")
        XCTAssertEqual(projectChildren[1].id, "area-2", "Backend second (sortOrder 2000)")
        
        let frontendTasks = treeViewModel.getChildren(of: "area-1")
        XCTAssertEqual(frontendTasks.count, 2, "Frontend should have 2 tasks")
        XCTAssertEqual(frontendTasks[0].id, "task-1", "Design UI first (sortOrder 100)")
        XCTAssertEqual(frontendTasks[1].id, "task-2", "Implement Components second (sortOrder 200)")
        
        let backendTasks = treeViewModel.getChildren(of: "area-2")
        XCTAssertEqual(backendTasks.count, 1, "Backend should have 1 task")
        XCTAssertEqual(backendTasks[0].id, "task-3", "Setup Database")
    }
    
    func testTreeViewModel_dataManagerPublisher_updatesNodesAutomatically() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()
        
        let initialNode = Node(
            id: "node-1",
            title: "Initial Node",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        mockDataManager.mockNodes = [initialNode]
        treeViewModel.setDataManager(mockDataManager)
        
        // Act - Load initially
        await treeViewModel.initialLoad()
        
        // Verify initial state
        XCTAssertEqual(treeViewModel.allNodes.count, 1)
        XCTAssertEqual(treeViewModel.allNodes[0].title, "Initial Node")
        
        // Act - Update DataManager nodes directly (simulating external update)
        let newNode = Node(
            id: "node-2",
            title: "New Node",
            nodeType: "task",
            parentId: nil,
            sortOrder: 500,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "low")
        )
        
        mockDataManager.nodes = [initialNode, newNode]
        
        // Give publisher time to propagate
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Assert - TreeViewModel should auto-update
        XCTAssertEqual(treeViewModel.allNodes.count, 2, "Should have 2 nodes after update")
        
        let rootNodes = treeViewModel.getRootNodes()
        XCTAssertEqual(rootNodes.count, 2)
        XCTAssertEqual(rootNodes[0].id, "node-2", "New node should be first (sortOrder 500)")
        XCTAssertEqual(rootNodes[1].id, "node-1", "Initial node should be second (sortOrder 1000)")
    }
    
    func testTreeViewModel_getParentChain_buildsCorrectChain() async throws {
        // Arrange
        let mockDataManager = MockDataManager()
        let treeViewModel = TreeViewModel()
        
        // Create deep hierarchy: root -> level1 -> level2 -> level3
        let root = Node(
            id: "root",
            title: "Root",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let level1 = Node(
            id: "level1",
            title: "Level 1",
            nodeType: "folder",
            parentId: "root",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let level2 = Node(
            id: "level2",
            title: "Level 2",
            nodeType: "folder",
            parentId: "level1",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        let level3 = Node(
            id: "level3",
            title: "Level 3",
            nodeType: "task",
            parentId: "level2",
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date(),
            taskData: TaskData(status: "todo", priority: "medium")
        )
        
        mockDataManager.mockNodes = [root, level1, level2, level3]
        treeViewModel.setDataManager(mockDataManager)
        
        // Act
        await treeViewModel.initialLoad()
        
        // Get parent chain for level3
        let parentChain = treeViewModel.getParentChain(for: level3)
        
        // Assert
        XCTAssertEqual(parentChain.count, 3, "Should have 3 parents")
        XCTAssertEqual(parentChain[0].id, "root", "First parent should be root")
        XCTAssertEqual(parentChain[1].id, "level1", "Second parent should be level1")
        XCTAssertEqual(parentChain[2].id, "level2", "Third parent should be level2")
    }
}