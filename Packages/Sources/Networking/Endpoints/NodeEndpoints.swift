import Foundation
import Models
import Core

private let logger = Logger.shared

public extension APIClient {
    // Node endpoints
    func getNodes(parentId: String? = nil) async throws -> [Node] {
        logger.log("📞 getNodes called with parentId: \(parentId ?? "nil")", category: "APIClient")
        let endpoint = parentId != nil ? "/nodes/?parent_id=\(parentId!)&limit=1000" : "/nodes/?limit=1000"
        logger.log("Endpoint: \(endpoint)", category: "APIClient")
        
        let nodes = try await makeRequest(
            endpoint: endpoint,
            responseType: [Node].self
        )
        
        logger.log("✅ Retrieved \(nodes.count) nodes", category: "APIClient")
        return nodes
    }
    
    /// Fetch ALL nodes for the user (for offline caching)
    func getAllNodes() async throws -> [Node] {
        logger.log("📞 APIClient.getAllNodes() called - fetching complete node tree", category: "APIClient")
        
        // Use max allowed limit to get all nodes (backend max is 1000)
        let endpoint = "/nodes/?limit=1000"
        logger.log("🌐 Endpoint: \(endpoint)", category: "APIClient")
        
        do {
            let nodes = try await makeRequest(
                endpoint: endpoint,
                responseType: [Node].self
            )
            
            logger.log("✅ API Response: Retrieved ALL \(nodes.count) nodes for offline cache", category: "APIClient")
            return nodes
        } catch {
            logger.log("❌ getAllNodes() failed: \(error)", level: .error, category: "APIClient")
            logger.log("📊 Error type: \(type(of: error))", level: .error, category: "APIClient")
            throw error
        }
    }
    
    func getNode(id: String) async throws -> Node {
        return try await makeRequest(
            endpoint: "/nodes/\(id)",
            responseType: Node.self
        )
    }
    
    func createNode(_ node: Node) async throws -> Node {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(node)
        
        return try await makeRequest(
            endpoint: "/nodes/",
            method: "POST",
            body: body,
            responseType: Node.self
        )
    }
    
    func createGenericNode(title: String, nodeType: String, parentId: String? = nil) async throws -> Node {
        // Validate input
        try InputValidator.validateTitle(title)
        if let parentId = parentId {
            try InputValidator.validateNodeId(parentId)
        }

        struct GenericNodeCreateRequest: Codable {
            let title: String
            let nodeType: String
            let parentId: String?
            let sortOrder: Int

            enum CodingKeys: String, CodingKey {
                case title
                case nodeType = "node_type"
                case parentId = "parent_id"
                case sortOrder = "sort_order"
            }
        }

        let nodeRequest = GenericNodeCreateRequest(
            title: InputValidator.sanitizeTitle(title),
            nodeType: nodeType,
            parentId: parentId,
            sortOrder: 1000
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(nodeRequest)
        
        return try await makeRequest(
            endpoint: "/nodes/",
            method: "POST",
            body: body,
            responseType: Node.self
        )
    }
    
    func createFolder(title: String, parentId: String? = nil) async throws -> Node {
        // Validate input
        try InputValidator.validateTitle(title)
        if let parentId = parentId {
            try InputValidator.validateNodeId(parentId)
        }

        struct FolderCreateRequest: Codable {
            let title: String
            let nodeType: String
            let parentId: String?
            let sortOrder: Int
            
            enum CodingKeys: String, CodingKey {
                case title
                case nodeType = "node_type"
                case parentId = "parent_id"
                case sortOrder = "sort_order"
            }
        }
        
        let folderRequest = FolderCreateRequest(
            title: InputValidator.sanitizeTitle(title),
            nodeType: "folder",
            parentId: parentId,
            sortOrder: 1000
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(folderRequest)
        
        return try await makeRequest(
            endpoint: "/nodes/",
            method: "POST",
            body: body,
            responseType: Node.self
        )
    }
    
    func createTask(title: String, parentId: String? = nil, description: String? = nil) async throws -> Node {
        // Validate input
        try InputValidator.validateTitle(title)
        try InputValidator.validateDescription(description)
        if let parentId = parentId {
            try InputValidator.validateNodeId(parentId)
        }

        struct TaskCreateRequest: Codable {
            let title: String
            let nodeType: String
            let parentId: String?
            let sortOrder: Int
            let taskData: TaskDataCreate
            
            enum CodingKeys: String, CodingKey {
                case title
                case nodeType = "node_type"
                case parentId = "parent_id"
                case sortOrder = "sort_order"
                case taskData = "task_data"
            }
        }
        
        struct TaskDataCreate: Codable {
            let status: String
            let description: String?
            let priority: String
        }
        
        let taskRequest = TaskCreateRequest(
            title: InputValidator.sanitizeTitle(title),
            nodeType: "task",
            parentId: parentId,
            sortOrder: 1000,
            taskData: TaskDataCreate(
                status: "todo",
                description: description,
                priority: "medium"
            )
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(taskRequest)
        
        return try await makeRequest(
            endpoint: "/nodes/",
            method: "POST",
            body: body,
            responseType: Node.self
        )
    }
    
    func createNote(title: String, parentId: String? = nil, body: String = "") async throws -> Node {
        // Validate input
        try InputValidator.validateTitle(title)
        if let parentId = parentId {
            try InputValidator.validateNodeId(parentId)
        }
        // Note body can be very long, no validation needed

        struct NoteCreateRequest: Codable {
            let title: String
            let nodeType: String
            let parentId: String?
            let sortOrder: Int
            let noteData: NoteDataCreate
            
            enum CodingKeys: String, CodingKey {
                case title
                case nodeType = "node_type"
                case parentId = "parent_id"
                case sortOrder = "sort_order"
                case noteData = "note_data"
            }
        }
        
        struct NoteDataCreate: Codable {
            let body: String
        }
        
        let noteRequest = NoteCreateRequest(
            title: title,
            nodeType: "note",
            parentId: parentId,
            sortOrder: 1000,
            noteData: NoteDataCreate(body: body.isEmpty ? " " : body)
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(noteRequest)
        
        return try await makeRequest(
            endpoint: "/nodes/",
            method: "POST",
            body: body,
            responseType: Node.self
        )
    }
    
    func toggleTaskCompletion(nodeId: String, currentlyCompleted: Bool) async throws -> Node {
        logger.info("📞 toggleTaskCompletion called", category: "APIClient")
        logger.debug("   - Node ID: \(nodeId)", category: "APIClient")
        logger.debug("   - Currently completed: \(currentlyCompleted)", category: "APIClient")
        logger.debug("   - Will set to: \(!currentlyCompleted)", category: "APIClient")
        
        // First, get the current node to preserve all fields
        let currentNode = try await getNode(id: nodeId)
        
        let newStatus = currentlyCompleted ? "todo" : "done"
        let newCompletedAt = currentlyCompleted ? nil : ISO8601DateFormatter().string(from: Date())
        
        logger.debug("Setting status to: \(newStatus)", category: "APIClient")
        logger.debug("Setting completedAt to: \(newCompletedAt ?? "nil")", category: "APIClient")
        
        let nodeUpdate = NodeUpdate(
            title: currentNode.title,
            parentId: currentNode.parentId,
            sortOrder: currentNode.sortOrder,
            taskData: TaskDataUpdate(
                status: newStatus,
                priority: currentNode.taskData?.priority,
                description: currentNode.taskData?.description,
                dueAt: currentNode.taskData?.dueAt,
                earliestStartAt: currentNode.taskData?.earliestStartAt,
                completedAt: newCompletedAt,
                archived: currentNode.taskData?.archived
            )
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(nodeUpdate)
        
        logger.debug("📤 Request body: \(String(data: body, encoding: .utf8) ?? "")", category: "APIClient")
        
        let result = try await makeRequest(
            endpoint: "/nodes/\(nodeId)",
            method: "PUT",
            body: body,
            responseType: Node.self
        )
        
        // Validate the response matches what we expected
        let actuallyCompleted = result.taskData?.completedAt != nil
        let expectedCompleted = !currentlyCompleted
        
        if actuallyCompleted != expectedCompleted {
            logger.error("❌ Task toggle failed - expected completed: \(expectedCompleted), got: \(actuallyCompleted)", category: "APIClient")
            logger.error("   Response task_data: \(String(describing: result.taskData))", category: "APIClient")
        } else {
            logger.info("✅ Task toggle successful", category: "APIClient")
        }
        
        logger.debug("   - Updated node: \(result.title)", category: "APIClient")
        logger.debug("   - New completion status: \(actuallyCompleted)", category: "APIClient")
        
        return result
    }
    
    // Removed full-Node update to prevent accidental overwrites.
    
    func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(update)
        
        return try await makeRequest(
            endpoint: "/nodes/\(id)",
            method: "PUT",
            body: body,
            responseType: Node.self
        )
    }
    
    func toggleTaskStatus(nodeId: String, currentStatus: String?) async throws -> Node {
        struct TaskStatusUpdate: Codable {
            let taskData: TaskDataUpdate
            
            enum CodingKeys: String, CodingKey {
                case taskData = "task_data"
            }
        }
        
        struct TaskDataUpdate: Codable {
            let status: String
            let completedAt: String?
            
            enum CodingKeys: String, CodingKey {
                case status
                case completedAt = "completed_at"
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(status, forKey: .status)
                // Always encode completedAt, even if nil (encodes as JSON null)
                if let completedAt = completedAt {
                    try container.encode(completedAt, forKey: .completedAt)
                } else {
                    try container.encodeNil(forKey: .completedAt)
                }
            }
        }
        
        // Toggle between 'todo' and 'done'
        let isCurrentlyCompleted = currentStatus == "done" || currentStatus == "completed"
        let newStatus = isCurrentlyCompleted ? "todo" : "done"
        let completedAt = newStatus == "done" ? ISO8601DateFormatter().string(from: Date()) : nil
        
        let update = TaskStatusUpdate(
            taskData: TaskDataUpdate(
                status: newStatus,
                completedAt: completedAt
            )
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(update)
        
        return try await makeRequest(
            endpoint: "/nodes/\(nodeId)",
            method: "PUT",
            body: body,
            responseType: Node.self
        )
    }
    
    /// Instantiate a template to create a copy with all its contents
    /// - Parameters:
    ///   - templateId: The template ID to instantiate
    ///   - name: Name for the instantiated copy
    ///   - parentId: Optional parent ID (if nil, uses template's target_node_id)
    /// - Returns: The created node
    func instantiateTemplate(templateId: String, name: String, parentId: String? = nil) async throws -> Node {
        logger.log("📞 Instantiating template: \(templateId) with name: \(name)", category: "NodeEndpoints")
        
        var endpoint = "/nodes/templates/\(templateId)/instantiate?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
        
        if let parentId = parentId {
            endpoint += "&parent_id=\(parentId)"
        }
        
        let response = try await makeRequest(
            endpoint: endpoint,
            method: "POST",
            responseType: Node.self
        )
        
        logger.log("✅ Template instantiated successfully", category: "NodeEndpoints")
        return response
    }
    
    func deleteNode(id: String) async throws {
        logger.log("📞 deleteNode called with id: \(id)", category: "APIClient")

        _ = try await makeRequest(
            endpoint: "/nodes/\(id)",
            method: "DELETE",
            responseType: EmptyResponse.self
        )

        logger.log("✅ Node deleted successfully", category: "APIClient")
    }

    /// Executes a smart folder rule to retrieve its dynamic contents.
    /// Smart folders are virtual containers that display nodes matching specific rules.
    ///
    /// - Parameter smartFolderId: The ID of the smart folder to execute
    /// - Returns: Array of nodes matching the smart folder's rule
    /// - Throws: APIError if the request fails
    func executeSmartFolderRule(smartFolderId: String) async throws -> [Node] {
        logger.log("📞 executeSmartFolderRule called with id: \(smartFolderId)", category: "APIClient")

        let endpoint = "/nodes/\(smartFolderId)/contents"
        logger.log("🌐 API Endpoint: \(endpoint)", category: "APIClient")
        logger.log("📡 Method: GET", category: "APIClient")

        do {
            let nodes = try await makeRequest(
                endpoint: endpoint,
                method: "GET",
                responseType: [Node].self
            )

            logger.log("✅ Smart folder executed successfully", category: "APIClient")
            logger.log("📦 Response: Received \(nodes.count) nodes", category: "APIClient")

            // Log response summary for debugging
            if nodes.isEmpty {
                logger.log("📤 No nodes returned from smart folder rule", category: "APIClient")
            } else {
                let nodeTypes = Dictionary(grouping: nodes, by: { $0.nodeType })
                    .mapValues { $0.count }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: ", ")
                logger.log("📊 Node types breakdown: \(nodeTypes)", category: "APIClient")
            }

            return nodes
        } catch {
            logger.log("❌ Smart folder API call failed", level: .error, category: "APIClient")
            logger.log("🔴 Endpoint: \(endpoint)", level: .error, category: "APIClient")
            logger.log("🔴 Error: \(error)", level: .error, category: "APIClient")
            throw error
        }
    }
}
