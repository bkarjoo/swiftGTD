import Foundation
import Models
import Core
import Networking

/// Manages offline operations queue for syncing when connection is restored
@MainActor
public class OfflineQueueManager: ObservableObject {
    public static let shared = OfflineQueueManager()
    private let logger = Logger.shared
    
    // Queue operation types
    public enum OperationType: String, Codable {
        case create = "create"
        case update = "update"
        case delete = "delete"
        case toggleTask = "toggle_task"
        case updateNode = "update_node"
        case reorder = "reorder"
    }
    
    // Queued operation
    public struct QueuedOperation: Codable, Identifiable {
        public let id = UUID()
        let type: OperationType
        let timestamp: Date
        let nodeId: String?
        let nodeData: Data? // Encoded node for create/update
        let parentId: String?
        let metadata: [String: String]
        
        public init(type: OperationType, nodeId: String? = nil, nodeData: Data? = nil, parentId: String? = nil, metadata: [String: String] = [:]) {
            self.type = type
            self.timestamp = Date()
            self.nodeId = nodeId
            self.nodeData = nodeData
            self.parentId = parentId
            self.metadata = metadata
        }
    }
    
    @Published public var pendingOperations: [QueuedOperation] = []
    @Published public var isSyncing = false {
        didSet {
            if isSyncing {
                logger.log("🔒 isSyncing set to true", category: "OfflineQueue")
            } else {
                logger.log("🔓 isSyncing set to false", category: "OfflineQueue")
            }
        }
    }
    
    private let queueFile = "offline_queue.json"
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var queueURL: URL {
        documentsDirectory.appendingPathComponent("Cache").appendingPathComponent(queueFile)
    }
    
    private init() {
        // Reset sync flag on startup (in case app crashed while syncing)
        isSyncing = false

        Task {
            await loadQueue()
        }
    }
    
    // MARK: - Queue Management
    
    /// Add a create operation to the queue
    public func queueCreate(node: Node) async {
        logger.log("📝 Queuing create operation for node: \(node.title)", category: "OfflineQueue")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let nodeData = try encoder.encode(node)
            
            let operation = QueuedOperation(
                type: .create,
                nodeId: node.id,
                nodeData: nodeData,
                parentId: node.parentId,
                metadata: ["title": node.title, "nodeType": node.nodeType]
            )
            
            pendingOperations.append(operation)
            await saveQueue()
            
            logger.log("✅ Queued create operation", category: "OfflineQueue")
        } catch {
            logger.log("❌ Failed to queue create: \(error)", category: "OfflineQueue", level: .error)
        }
    }
    
    /// Add an update operation to the queue
    public func queueUpdate(node: Node) async {
        logger.log("📝 Queuing update operation for node: \(node.id)", category: "OfflineQueue")
        
        // Remove any existing update for this node (keep only latest)
        pendingOperations.removeAll { $0.type == .update && $0.nodeId == node.id }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let nodeData = try encoder.encode(node)
            
            let operation = QueuedOperation(
                type: .update,
                nodeId: node.id,
                nodeData: nodeData,
                metadata: ["title": node.title]
            )
            
            pendingOperations.append(operation)
            await saveQueue()
            
            logger.log("✅ Queued update operation", category: "OfflineQueue")
        } catch {
            logger.log("❌ Failed to queue update: \(error)", category: "OfflineQueue", level: .error)
        }
    }
    
    /// Add a delete operation to the queue
    public func queueDelete(nodeId: String, title: String) async {
        logger.log("📝 Queuing delete operation for node: \(nodeId)", category: "OfflineQueue")
        
        // Remove any create/update operations for this node
        pendingOperations.removeAll { $0.nodeId == nodeId && ($0.type == .create || $0.type == .update) }
        
        let operation = QueuedOperation(
            type: .delete,
            nodeId: nodeId,
            metadata: ["title": title]
        )
        
        pendingOperations.append(operation)
        await saveQueue()
        
        logger.log("✅ Queued delete operation", category: "OfflineQueue")
    }
    
    /// Add a toggle task operation to the queue
    public func queueToggleTask(nodeId: String, completed: Bool) async {
        logger.log("📝 Queuing toggle task operation for node: \(nodeId)", category: "OfflineQueue")

        // Remove any existing toggle for this node (keep only latest)
        pendingOperations.removeAll { $0.type == .toggleTask && $0.nodeId == nodeId }

        let operation = QueuedOperation(
            type: .toggleTask,
            nodeId: nodeId,
            metadata: ["completed": String(completed)]
        )

        pendingOperations.append(operation)
        await saveQueue()

        logger.log("✅ Queued toggle task operation", category: "OfflineQueue")
    }

    /// Queue a node update operation
    public func queueNodeUpdate(nodeId: String, update: NodeUpdate) async {
        logger.log("📝 Queuing node update operation for node: \(nodeId)", category: "OfflineQueue")

        // Remove any existing update for this node (keep only latest)
        pendingOperations.removeAll { $0.type == .updateNode && $0.nodeId == nodeId }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let updateData = try encoder.encode(update)

            let operation = QueuedOperation(
                type: .updateNode,
                nodeId: nodeId,
                nodeData: updateData,
                metadata: ["title": update.title]
            )

            pendingOperations.append(operation)
            await saveQueue()

            logger.log("✅ Queued node update operation", category: "OfflineQueue")
        } catch {
            logger.log("❌ Failed to queue node update: \(error)", category: "OfflineQueue", level: .error)
        }
    }

    /// Queue a reorder operation for nodes
    public func queueReorder(nodeIds: [String]) async {
        logger.log("📝 Queuing reorder operation for \(nodeIds.count) nodes", category: "OfflineQueue")

        // Remove any existing reorder operations for these nodes
        pendingOperations.removeAll { operation in
            if operation.type == .reorder,
               let existingNodeIds = operation.metadata["nodeIds"]?.components(separatedBy: ",") {
                // Remove if any nodes overlap
                return !Set(existingNodeIds).isDisjoint(with: Set(nodeIds))
            }
            return false
        }

        let operation = QueuedOperation(
            type: .reorder,
            nodeId: nil,
            nodeData: nil,
            metadata: ["nodeIds": nodeIds.joined(separator: ","), "count": String(nodeIds.count)]
        )

        pendingOperations.append(operation)
        await saveQueue()

        logger.log("✅ Queued reorder operation", category: "OfflineQueue")
    }
    
    // MARK: - Persistence
    
    private func saveQueue() async {
        let pendingOperations = self.pendingOperations
        let queueURL = self.queueURL
        let documentsDirectory = self.documentsDirectory

        await Task.detached(priority: .background) { [pendingOperations, queueURL, documentsDirectory] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(pendingOperations)

                // Ensure directory exists
                let cacheDir = documentsDirectory.appendingPathComponent("Cache")
                if !FileManager.default.fileExists(atPath: cacheDir.path) {
                    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                }

                try data.write(to: queueURL)
                Logger.shared.log("💾 Saved \(pendingOperations.count) pending operations", category: "OfflineQueue")
            } catch {
                Logger.shared.log("❌ Failed to save queue: \(error)", category: "OfflineQueue", level: .error)
            }
        }.value
    }
    
    private func loadQueue() async {
        let queueURL = self.queueURL

        let loadedOperations: [QueuedOperation]? = await Task.detached(priority: .background) {
            let queueURL = queueURL
            guard FileManager.default.fileExists(atPath: queueURL.path) else {
                Logger.shared.log("📦 No offline queue found", category: "OfflineQueue")
                return nil
            }

            do {
                let data = try Data(contentsOf: queueURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let operations = try decoder.decode([QueuedOperation].self, from: data)
                Logger.shared.log("📦 Loaded \(operations.count) pending operations", category: "OfflineQueue")
                return operations
            } catch {
                Logger.shared.log("❌ Failed to load queue: \(error)", category: "OfflineQueue", level: .error)
                return nil
            }
        }.value

        if let operations = loadedOperations {
            self.pendingOperations = operations
        }
    }
    
    /// Remove a create operation for a node that was deleted before syncing
    public func removeCreateOperation(nodeId: String) async {
        pendingOperations.removeAll { $0.type == .create && $0.nodeId == nodeId }
        await saveQueue()
        logger.log("🗑️ Removed create operation for node: \(nodeId)", category: "OfflineQueue")
    }
    
    /// Clear all pending operations
    public func clearQueue() async {
        pendingOperations.removeAll()
        await saveQueue()
        logger.log("🗑️ Cleared offline queue", category: "OfflineQueue")
    }
    
    /// Get a human-readable summary of pending operations
    public func getPendingSummary() -> String {
        let grouped = Dictionary(grouping: pendingOperations, by: { $0.type })
        var summary: [String] = []
        
        if let creates = grouped[.create], !creates.isEmpty {
            summary.append("\(creates.count) new nodes")
        }
        if let updates = grouped[.update], !updates.isEmpty {
            summary.append("\(updates.count) updates")
        }
        if let deletes = grouped[.delete], !deletes.isEmpty {
            summary.append("\(deletes.count) deletions")
        }
        if let toggles = grouped[.toggleTask], !toggles.isEmpty {
            summary.append("\(toggles.count) task status changes")
        }
        
        return summary.isEmpty ? "No pending changes" : summary.joined(separator: ", ")
    }
    
    // MARK: - Sync Processing
    
    /// Process all pending operations
    public func processPendingOperations() async -> (succeeded: Int, failed: Int, tempIdMap: [String: String]) {
        guard !pendingOperations.isEmpty else {
            logger.log("📭 No pending operations to sync", category: "OfflineQueue")
            // Ensure isSyncing is false even if queue is empty
            if isSyncing {
                logger.log("⚠️ Resetting stuck isSyncing flag", category: "OfflineQueue")
                isSyncing = false
            }
            return (0, 0, [:])
        }

        guard !isSyncing else {
            logger.log("⏳ Already syncing - skipping duplicate call", category: "OfflineQueue")
            return (0, 0, [:])
        }

        isSyncing = true
        defer {
            isSyncing = false
            logger.log("🔓 Sync lock released", category: "OfflineQueue")
        }
        
        logger.log("🔄 Starting sync of \(pendingOperations.count) operations", category: "OfflineQueue")
        
        var succeeded = 0
        var failed = 0
        var tempIdMap: [String: String] = [:]  // Maps temp IDs to server IDs
        var processedOperations: [QueuedOperation] = []
        
        // Process operations in order (creates first, then updates, then reorders, then deletes)
        let sortedOps = pendingOperations.sorted { op1, op2 in
            let order = [OperationType.create: 0, .update: 1, .updateNode: 1, .toggleTask: 2, .reorder: 3, .delete: 4]
            return (order[op1.type] ?? 99) < (order[op2.type] ?? 99)
        }
        
        // SAFETY CHECK: Warn if there are many deletes
        let deleteCount = sortedOps.filter { $0.type == .delete }.count
        if deleteCount > 10 {
            logger.log("⚠️ WARNING: About to sync \(deleteCount) delete operations!", category: "OfflineQueue", level: .warning)
            // Could add user confirmation here in the future
        }
        
        for operation in sortedOps {
            logger.log("⚙️ Processing \(operation.type) operation: \(operation.metadata["title"] ?? operation.nodeId ?? "unknown")", category: "OfflineQueue")
            let success = await processOperation(operation, tempIdMap: &tempIdMap)
            if success {
                succeeded += 1
                processedOperations.append(operation)
                logger.log("✅ Successfully processed \(operation.type) operation", category: "OfflineQueue")
            } else {
                failed += 1
                logger.log("❌ Failed to sync operation: \(operation.type) for \(operation.metadata["title"] ?? operation.nodeId ?? "unknown")", category: "OfflineQueue", level: .error)
            }
        }

        // Remove successfully processed operations
        let beforeCount = pendingOperations.count
        pendingOperations.removeAll { op in processedOperations.contains { $0.id == op.id } }
        let removedCount = beforeCount - pendingOperations.count
        logger.log("🧹 Removed \(removedCount) processed operations, \(pendingOperations.count) remaining", category: "OfflineQueue")
        await saveQueue()
        
        logger.log("✅ Sync complete: \(succeeded) succeeded, \(failed) failed", category: "OfflineQueue")
        
        return (succeeded, failed, tempIdMap)
    }
    
    private func processOperation(_ operation: QueuedOperation, tempIdMap: inout [String: String]) async -> Bool {
        let api = APIClient.shared

        logger.log("🔧 Processing \(operation.type) operation", category: "OfflineQueue")

        switch operation.type {
        case .create:
            guard let nodeData = operation.nodeData else {
                logger.log("❌ No node data in create operation", category: "OfflineQueue", level: .error)
                return false
            }

            guard let node = try? JSONDecoder().decode(Node.self, from: nodeData) else {
                logger.log("❌ Failed to decode node data", category: "OfflineQueue", level: .error)
                return false
            }
            
            // Check if parent ID needs mapping
            let actualParentId = node.parentId.flatMap { tempIdMap[$0] ?? $0 }
            
            do {
                // Create the node on the server
                let createdNode: Node
                switch node.nodeType {
                case "folder":
                    createdNode = try await api.createFolder(title: node.title, parentId: actualParentId)
                case "task":
                    createdNode = try await api.createTask(
                        title: node.title,
                        parentId: actualParentId,
                        description: node.taskData?.description
                    )
                case "note":
                    createdNode = try await api.createNote(
                        title: node.title,
                        parentId: actualParentId,
                        body: node.noteData?.body ?? ""
                    )
                default:
                    createdNode = try await api.createGenericNode(
                        title: node.title,
                        nodeType: node.nodeType,
                        parentId: actualParentId
                    )
                }
                
                // Map temp ID to server ID
                tempIdMap[node.id] = createdNode.id
                logger.log("✅ Created node on server: \(node.title) (temp: \(node.id) → server: \(createdNode.id))", category: "OfflineQueue")
                return true
            } catch {
                logger.log("❌ Failed to create node: \(error)", category: "OfflineQueue", level: .error)
                return false
            }
            
        case .delete:
            guard let nodeId = operation.nodeId else { return false }
            
            // Check if this is a temp ID that was never synced
            if nodeId.hasPrefix("temp-") {
                // This was created offline and never synced, just skip
                logger.log("⏭️ Skipping delete for unsynced temp node: \(nodeId)", category: "OfflineQueue")
                return true
            }
            
            // Map to server ID if needed
            let actualNodeId = tempIdMap[nodeId] ?? nodeId
            
            do {
                try await api.deleteNode(id: actualNodeId)
                logger.log("✅ Deleted node on server: \(actualNodeId)", category: "OfflineQueue")
                return true
            } catch {
                logger.log("❌ Failed to delete node: \(error)", category: "OfflineQueue", level: .error)
                return false
            }
            
        case .toggleTask:
            guard let nodeId = operation.nodeId,
                  let completedStr = operation.metadata["completed"],
                  let completed = Bool(completedStr) else { return false }
            
            // Map to server ID if needed
            let actualNodeId = tempIdMap[nodeId] ?? nodeId
            
            do {
                _ = try await api.toggleTaskCompletion(nodeId: actualNodeId, currentlyCompleted: !completed)
                logger.log("✅ Toggled task on server: \(actualNodeId) to \(completed ? "completed" : "uncompleted")", category: "OfflineQueue")
                return true
            } catch {
                logger.log("❌ Failed to toggle task: \(error)", category: "OfflineQueue", level: .error)
                return false
            }
            
        case .update:
            // Update is now handled by updateNode case below
            logger.log("⚠️ Legacy update operation - use updateNode instead", category: "OfflineQueue")
            return false

        case .updateNode:
            guard let nodeId = operation.nodeId,
                  let updateData = operation.nodeData else { return false }

            // Map to server ID if needed
            let actualNodeId = tempIdMap[nodeId] ?? nodeId

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let update = try decoder.decode(NodeUpdate.self, from: updateData)

                _ = try await api.updateNode(id: actualNodeId, update: update)
                logger.log("✅ Updated node on server: \(actualNodeId) with title: \(update.title)", category: "OfflineQueue")
                return true
            } catch {
                logger.log("❌ Failed to update node: \(error)", category: "OfflineQueue", level: .error)
                return false
            }

        case .reorder:
            guard let nodeIdsString = operation.metadata["nodeIds"] else {
                logger.log("❌ No node IDs in reorder operation", category: "OfflineQueue", level: .error)
                return false
            }

            let nodeIds = nodeIdsString.components(separatedBy: ",")

            // Map any temp IDs to server IDs
            let actualNodeIds = nodeIds.map { tempIdMap[$0] ?? $0 }

            do {
                try await api.reorderNodes(nodeIds: actualNodeIds)
                logger.log("✅ Reordered \(actualNodeIds.count) nodes on server", category: "OfflineQueue")
                return true
            } catch {
                logger.log("❌ Failed to reorder nodes: \(error)", category: "OfflineQueue", level: .error)
                return false
            }
        }
    }
}