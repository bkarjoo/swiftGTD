import Foundation
import Models
import Networking

/// Base mock API client that provides default implementations for all protocol methods
/// Subclasses can override specific methods for testing
open class MockAPIClientBase: APIClientProtocol {

    // Auth
    open func setAuthToken(_ token: String?) {
        // Default no-op
    }

    open func getCurrentUser() async throws -> User {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    // Nodes - Core operations
    open func getNodes(parentId: String?) async throws -> [Node] {
        return []
    }

    open func getAllNodes() async throws -> [Node] {
        return []
    }

    open func getNode(id: String) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func createNode(_ node: Node) async throws -> Node {
        return node
    }

    open func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func deleteNode(id: String) async throws {
        // Default no-op
    }

    // Tags
    open func getTags() async throws -> [Tag] {
        return []
    }

    open func searchTags(query: String, limit: Int) async throws -> [Tag] {
        return []
    }

    open func createTag(name: String, description: String?, color: String?) async throws -> Tag {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func attachTagToNode(nodeId: String, tagId: String) async throws {
        // Default no-op
    }

    open func detachTagFromNode(nodeId: String, tagId: String) async throws {
        // Default no-op
    }

    // Task operations
    open func toggleTaskCompletion(nodeId: String, currentlyCompleted: Bool) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    // Specialized node creation
    open func createFolder(title: String, parentId: String?) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func createTask(title: String, parentId: String?, description: String?) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func createNote(title: String, parentId: String?, body: String) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func createGenericNode(title: String, nodeType: String, parentId: String?) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    // Smart folder operations
    open func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        return []
    }

    // Template operations
    open func instantiateTemplate(templateId: String, name: String, parentId: String?) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    open func instantiateTemplate(templateId: String, parentId: String?) async throws -> Node {
        throw NSError(domain: "MockAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    // Settings operations
    open func getDefaultNode() async throws -> String? {
        return nil
    }

    open func setDefaultNode(nodeId: String?) async throws {
        // Default no-op
    }

    // Rule operations
    open func getRules(includePublic: Bool, includeSystem: Bool) async throws -> RuleListResponse {
        return RuleListResponse(rules: [], total: 0)
    }
}