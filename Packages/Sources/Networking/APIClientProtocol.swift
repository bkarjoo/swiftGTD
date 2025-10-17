import Foundation
import Models

/// Protocol for APIClient to enable dependency injection and testing
public protocol APIClientProtocol {
    // Auth
    func setAuthToken(_ token: String?)
    func getCurrentUser() async throws -> User
    
    // Nodes - Core operations
    func getNodes(parentId: String?) async throws -> [Node]
    func getAllNodes() async throws -> [Node]
    func getNode(id: String) async throws -> Node
    func createNode(_ node: Node) async throws -> Node
    func updateNode(id: String, update: NodeUpdate) async throws -> Node
    func deleteNode(id: String) async throws
    func reorderNodes(nodeIds: [String]) async throws
    
    // Tags
    func getTags() async throws -> [Tag]
    func searchTags(query: String, limit: Int) async throws -> [Tag]
    func createTag(name: String, description: String?, color: String?) async throws -> Tag
    func updateTag(id: String, name: String) async throws -> (tag: Tag, wasMerged: Bool)
    func deleteTag(id: String) async throws
    func attachTagToNode(nodeId: String, tagId: String) async throws
    func detachTagFromNode(nodeId: String, tagId: String) async throws
    
    // Task operations
    func toggleTaskCompletion(nodeId: String, currentlyCompleted: Bool) async throws -> Node
    
    // Specialized node creation
    func createFolder(title: String, parentId: String?, description: String?) async throws -> Node
    func createTask(title: String, parentId: String?, description: String?) async throws -> Node
    func createNote(title: String, parentId: String?, body: String) async throws -> Node
    func createGenericNode(title: String, nodeType: String, parentId: String?) async throws -> Node

    /// Smart folder operations
    /// Executes a smart folder's rule to retrieve its dynamic contents
    func executeSmartFolderRule(smartFolderId: String) async throws -> [Node]

    /// Template operations
    /// Instantiates a template with optional parent override
    func instantiateTemplate(templateId: String, name: String, parentId: String?) async throws -> Node
    func instantiateTemplate(templateId: String, parentId: String?) async throws -> Node

    /// Settings operations
    /// Gets and sets the default folder for quick task creation
    func getDefaultNode() async throws -> String?
    func setDefaultNode(nodeId: String?) async throws

    /// Rule operations
    func getRules(includePublic: Bool, includeSystem: Bool) async throws -> RuleListResponse
}

// Make APIClient conform to the protocol
extension APIClient: APIClientProtocol {}