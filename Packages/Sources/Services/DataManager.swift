import Foundation
import SwiftUI
import Models
import Networking
import Core
import Combine

private let logger = Logger.shared

@MainActor
public class DataManager: ObservableObject {
    @Published public var nodes: [Node] = []
    @Published public var tags: [Tag] = []
    @Published public var selectedNode: Node?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var isOffline = false
    @Published public var lastSyncDate: Date?
    
    private let api: APIClientProtocol
    private let cacheManager = CacheManager.shared
    private let offlineQueue = OfflineQueueManager.shared
    private let networkMonitor: NetworkMonitorProtocol
    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?  // Track current sync task
    
    public init(
        apiClient: APIClientProtocol = APIClient.shared,
        networkMonitor: NetworkMonitorProtocol? = nil
    ) {
        self.api = apiClient
        self.networkMonitor = networkMonitor ?? NetworkMonitorFactory.shared
        
        // Monitor network status - handle both NetworkMonitor and TestableNetworkMonitor
        if let observableMonitor = networkMonitor as? NetworkMonitor {
            observableMonitor.$isConnected
                .sink { [weak self] isConnected in
                    guard let self = self else { return }
                    
                    let wasOffline = self.isOffline
                    self.isOffline = !isConnected
                    
                    if isConnected {
                        
                        // Trigger auto-sync if coming back online with pending operations
                        if wasOffline && !self.offlineQueue.pendingOperations.isEmpty {
                            logger.log("🔄 Network restored - triggering auto-sync of pending operations", category: "DataManager")
                            self.syncTask = Task {
                                await self.syncPendingOperations()
                            }
                        }
                    } else {
                    }
                }
                .store(in: &cancellables)
        } else if let testableMonitor = networkMonitor as? TestableNetworkMonitor {
            // For TestableNetworkMonitor, we can observe it too since it's also ObservableObject
            testableMonitor.$isConnected
                .sink { [weak self] isConnected in
                    guard let self = self else { return }
                    
                    let wasOffline = self.isOffline
                    self.isOffline = !isConnected
                    
                    if isConnected {
                        
                        // Trigger auto-sync if coming back online with pending operations
                        if wasOffline && !self.offlineQueue.pendingOperations.isEmpty {
                            logger.log("🔄 [TEST] Network restored - triggering auto-sync of pending operations", category: "DataManager")
                            self.syncTask = Task {
                                await self.syncPendingOperations()
                            }
                        }
                    } else {
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    public func loadNodes(parentId: String? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            nodes = try await api.getNodes(parentId: parentId)
        } catch {
            logger.log("❌ Failed to load nodes: \(error)", category: "DataManager")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    public func loadTags() async {
        do {
            tags = try await api.getTags()
        } catch {
            logger.log("❌ Failed to load tags: \(error)", category: "DataManager")
            errorMessage = error.localizedDescription
        }
    }
    
    public func createNode(title: String, type: String, content: String? = nil, parentId: String? = nil, tags: [Tag]? = nil) async -> Node? {
        
        if networkMonitor.isConnected {
            // Online - create via API
            do {
                let createdNode: Node
                
                switch type {
                case "folder":
                    createdNode = try await api.createFolder(title: title, parentId: parentId, description: content)
                case "task":
                    createdNode = try await api.createTask(title: title, parentId: parentId, description: content)
                case "note":
                    createdNode = try await api.createNote(title: title, parentId: parentId, body: content ?? "")
                case "template", "smart_folder":
                    // Use generic node creation with the actual type
                    createdNode = try await api.createGenericNode(title: title, nodeType: type, parentId: parentId)
                default:
                    logger.log("❌ Unknown node type: \(type)", category: "DataManager")
                    errorMessage = "Unknown node type: \(type)"
                    return nil
                }
                
                // Add to local nodes array and update cache in one go
                nodes.append(createdNode)
                nodes.sort { $0.sortOrder < $1.sortOrder }
                
                // Update cache without triggering another update
                await cacheManager.saveNodes(nodes)
                
                return createdNode
            } catch {
                logger.log("❌ Failed to create node: \(error)", category: "DataManager")
                errorMessage = error.localizedDescription
                return nil
            }
        } else {
            // Offline - create locally and queue for sync

            // Generate a temporary ID with clear prefix
            let tempId = "temp-\(UUID().uuidString)"
            
            // Find highest sort order for siblings
            let siblings = nodes.filter { $0.parentId == parentId }
            let maxSortOrder = siblings.map { $0.sortOrder }.max() ?? 0
            
            // Create the node locally
            var newNode: Node
            
            switch type {
            case "task":
                newNode = Node(
                    id: tempId,
                    title: title,
                    nodeType: type,
                    parentId: parentId,
                    sortOrder: maxSortOrder + 1000,
                    createdAt: Date(),
                    updatedAt: Date(),
                    taskData: TaskData(
                        description: content,
                        status: "todo",
                        priority: "medium",
                        dueAt: nil,
                        earliestStartAt: nil,
                        completedAt: nil,
                        archived: false
                    )
                )
            case "folder":
                newNode = Node(
                    id: tempId,
                    title: title,
                    nodeType: type,
                    parentId: parentId,
                    sortOrder: maxSortOrder + 1000,
                    createdAt: Date(),
                    updatedAt: Date(),
                    folderData: FolderData(description: content)
                )
            case "note":
                newNode = Node(
                    id: tempId,
                    title: title,
                    nodeType: type,
                    parentId: parentId,
                    sortOrder: maxSortOrder + 1000,
                    createdAt: Date(),
                    updatedAt: Date(),
                    noteData: NoteData(body: content ?? "")
                )
            default:
                newNode = Node(
                    id: tempId,
                    title: title,
                    nodeType: type,
                    parentId: parentId,
                    sortOrder: maxSortOrder + 1000,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
            
            // Add to local nodes and sort in one update
            nodes.append(newNode)
            nodes.sort { $0.sortOrder < $1.sortOrder }
            
            // Queue for sync
            await offlineQueue.queueCreate(node: newNode)
            
            // Save to cache without triggering another update
            await cacheManager.saveNodes(nodes)
            
            errorMessage = "Created offline - will sync when connected"
            
            return newNode
        }
    }
    
    public func updateNode(_ nodeId: String, update: NodeUpdate) async -> Node? {

        // Find the node to update
        guard let nodeIndex = nodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.log("❌ Node not found: \(nodeId)", category: "DataManager")
            return nil
        }

        let oldNode = nodes[nodeIndex]

        if networkMonitor.isConnected {
            // Online - update via API
            do {
                let updatedNode = try await api.updateNode(id: nodeId, update: update)

                // Clear any previous error on success
                errorMessage = nil

                // Update local array
                nodes[nodeIndex] = updatedNode

                // Update cache
                await cacheManager.saveNodes(nodes)

                return updatedNode
            } catch {
                logger.log("❌ Failed to update node: \(error)", category: "DataManager")
                errorMessage = error.localizedDescription
                return nil
            }
        } else {
            // Offline - queue the update operation

            // Queue the update operation
            await offlineQueue.queueNodeUpdate(nodeId: nodeId, update: update)

            // Create optimistic local update
            // Since Node properties are immutable, we need to reconstruct it
            let updatedNode = Node(
                id: oldNode.id,
                title: update.title,  // Use the new title
                nodeType: oldNode.nodeType,
                parentId: update.parentId ?? oldNode.parentId,
                ownerId: oldNode.ownerId,
                createdAt: oldNode.createdAt,
                updatedAt: ISO8601DateFormatter().string(from: Date()),  // Update timestamp
                sortOrder: update.sortOrder,
                isList: oldNode.isList,
                childrenCount: oldNode.childrenCount,
                tags: oldNode.tags,
                taskData: oldNode.taskData,  // Task data preserved from original
                noteData: update.noteData != nil ? NoteData(
                    body: update.noteData?.body
                ) : oldNode.noteData,
                templateData: oldNode.templateData,  // Template data preserved from original
                smartFolderData: oldNode.smartFolderData,  // Smart folder data preserved from original
                folderData: update.folderData != nil ? FolderData(
                    description: update.folderData?.description
                ) : oldNode.folderData
            )

            // Update local array optimistically
            nodes[nodeIndex] = updatedNode

            // Update cache with optimistic change
            await cacheManager.saveNodes(nodes)


            return updatedNode
        }
    }
    
    public func deleteNode(_ node: Node) async {
        
        if networkMonitor.isConnected {
            // Online - delete via API
            do {
                try await api.deleteNode(id: node.id)
                
                // Clear any previous error on success
                errorMessage = nil
                
                // Remove the node and all its descendants
                var nodesToRemove = Set<String>()
                nodesToRemove.insert(node.id)
                
                // Find all descendants recursively
                func findDescendants(of parentId: String) {
                    let children = nodes.filter { $0.parentId == parentId }
                    for child in children {
                        nodesToRemove.insert(child.id)
                        findDescendants(of: child.id)
                    }
                }
                findDescendants(of: node.id)
                
                let oldCount = nodes.count
                nodes.removeAll { nodesToRemove.contains($0.id) }
                let newCount = nodes.count
                
                // Update cache
                await cacheManager.saveNodes(nodes)
            } catch {
                logger.log("❌ Failed to delete node: \(error)", category: "DataManager")
                errorMessage = error.localizedDescription
            }
        } else {
            // Offline - delete locally and queue for sync

            // Queue for sync (unless it's a temp node that was created offline)
            if !node.id.hasPrefix("temp-") {
                // This is a real server node, queue the deletion
                await offlineQueue.queueDelete(nodeId: node.id, title: node.title)
            } else {
                // This was created offline - remove it from create queue instead
                await offlineQueue.removeCreateOperation(nodeId: node.id)
            }
            
            // Remove the node and all its descendants from local nodes
            var nodesToRemove = Set<String>()
            nodesToRemove.insert(node.id)
            
            // Find all descendants recursively
            func findDescendants(of parentId: String) {
                let children = nodes.filter { $0.parentId == parentId }
                for child in children {
                    nodesToRemove.insert(child.id)
                    findDescendants(of: child.id)
                }
            }
            findDescendants(of: node.id)
            
            nodes.removeAll { nodesToRemove.contains($0.id) }
            
            // Save to cache
            await cacheManager.saveNodes(nodes)
            
            errorMessage = "Deleted offline - will sync when connected"
        }
    }
    
    /// Perform a full sync of all user data
    public func syncAllData() async {
        isLoading = true
        errorMessage = nil

        if networkMonitor.isConnected {
            // Online - fetch from API and cache
            do {
                // Fetch ALL data
                async let fetchedNodes = api.getAllNodes()
                async let fetchedTags = api.getTags()
                // Rules will be added when API supports them

                let (allNodes, allTags) = try await (fetchedNodes, fetchedTags)

                // SAFETY CHECK: Don't wipe data if server returns empty when we had data
                if allNodes.isEmpty && !nodes.isEmpty {
                    logger.log("⚠️ Server returned empty nodes but we have \(nodes.count) cached - keeping cache", category: "DataManager", level: .warning)
                    errorMessage = "Server returned no data - using cache"
                    await loadFromCache()
                    isLoading = false
                    return
                }

                // Update local state
                self.nodes = allNodes
                self.tags = allTags

                // Save to cache
                await cacheManager.saveNodes(allNodes)
                await cacheManager.saveTags(allTags)
                await cacheManager.saveMetadata(
                    nodeCount: allNodes.count,
                    tagCount: allTags.count,
                    ruleCount: 0  // Will be updated when rules are supported
                )

                self.lastSyncDate = Date()
                logger.log("✅ Sync completed", category: "DataManager")

            } catch {
                logger.log("❌ API call failed with error: \(error)", category: "DataManager", level: .error)
                errorMessage = "Sync failed. Loading from cache..."

                // Fall back to cache
                await loadFromCache()
            }
        } else {
            // Offline - load from cache
            await loadFromCache()
        }

        isLoading = false
    }
    
    /// Sync pending offline operations
    public func syncPendingOperations() async {
        // Cancel any existing sync task to prevent duplicates
        if let existingTask = syncTask, !existingTask.isCancelled {
            logger.log("⚠️ Cancelling existing sync task to prevent duplicates", category: "DataManager")
            existingTask.cancel()
        }

        // Add delay to debounce rapid network changes (like subway WiFi)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

        // Check if cancelled during delay
        if Task.isCancelled {
            return
        }

        // Process the queue
        let (succeeded, failed, tempIdMap) = await offlineQueue.processPendingOperations()

        if succeeded > 0 || failed > 0 {
            logger.log("✅ Sync completed: \(succeeded) succeeded, \(failed) failed", category: "DataManager")

            // Replace temp IDs in local nodes
            if !tempIdMap.isEmpty {
                await replaceTempIds(tempIdMap)
            }

            // Refresh data from server after successful sync
            if succeeded > 0 {
                await syncAllData()
            }

            // Update error message if there were failures
            if failed > 0 {
                errorMessage = "\(failed) operations failed to sync"
            } else if succeeded > 0 {
                errorMessage = nil
            }
        }
    }
    
    /// Replace temporary IDs with server IDs in local nodes
    private func replaceTempIds(_ tempIdMap: [String: String]) async {
        var updated = false
        
        // Update node IDs
        for (tempId, serverId) in tempIdMap {
            if let index = nodes.firstIndex(where: { $0.id == tempId }) {
                var node = nodes[index]
                // Create a new node with the server ID
                let updatedNode = Node(
                    id: serverId,
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
                nodes[index] = updatedNode
                updated = true
            }
        }
        
        // Update parent IDs that reference temp IDs
        for i in 0..<nodes.count {
            if let parentId = nodes[i].parentId,
               let newParentId = tempIdMap[parentId] {
                let node = nodes[i]
                let updatedNode = Node(
                    id: node.id,
                    title: node.title,
                    nodeType: node.nodeType,
                    parentId: newParentId,
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
                nodes[i] = updatedNode
                updated = true
            }
        }
        
        // Save updated nodes to cache
        if updated {
            await cacheManager.saveNodes(nodes)
        }
    }
    
    /// Load data from local cache
    private func loadFromCache() async {

        if let cachedNodes = await cacheManager.loadNodes() {
            self.nodes = cachedNodes
        } else {
            logger.log("⚠️ No nodes found in cache", category: "DataManager")
        }

        if let cachedTags = await cacheManager.loadTags() {
            self.tags = cachedTags
        } else {
            logger.log("⚠️ No tags found in cache", category: "DataManager")
        }

        if let metadata = await cacheManager.loadMetadata() {
            self.lastSyncDate = metadata.lastSyncDate
        } else {
            logger.log("⚠️ No cache metadata found", category: "DataManager")
        }

    }
    
    public func toggleNodeCompletion(_ node: Node) async -> Node? {

        guard node.nodeType == "task" else {
            logger.log("⚠️ Not a task node, returning nil", category: "DataManager")
            return nil
        }

        logger.log("🔄 Toggling task: \(node.id) - \(node.title)", category: "DataManager")
        logger.log("   Current status: \(node.taskData?.status ?? "unknown")", category: "DataManager")
        
        if networkMonitor.isConnected {
            // Online - toggle via API
            do {
                let isCurrentlyCompleted = node.taskData?.status == "done"
                
                let updatedNode = try await api.toggleTaskCompletion(
                    nodeId: node.id,
                    currentlyCompleted: isCurrentlyCompleted
                )
                
                // Clear any previous error on success
                errorMessage = nil
                
                // Update local nodes array
                logger.log("📝 Looking for node \(updatedNode.id) in \(nodes.count) nodes", category: "DataManager")

                if let index = nodes.firstIndex(where: { $0.id == updatedNode.id }) {
                    logger.log("✅ Found node at index \(index)", category: "DataManager")
                    nodes[index] = updatedNode

                    // Update cache
                    await cacheManager.saveNodes(nodes)
                    logger.log("✅ Updated task completion status for: \(updatedNode.title)", category: "DataManager")
                } else {
                    logger.log("⚠️ Node \(updatedNode.id) not found in main array", category: "DataManager")

                    // This shouldn't happen - the node should exist in the main array
                    // Do a targeted refresh to restore consistency
                    logger.log("🔄 Performing targeted refresh for node \(updatedNode.id)", category: "DataManager")
                    await refreshNode(updatedNode.id)
                }
                
                return updatedNode
            } catch {
                logger.log("❌ Failed to toggle task completion: \(error)", category: "DataManager")
                errorMessage = error.localizedDescription
                return nil
            }
        } else {
            // Offline - toggle locally and queue for sync

            guard let taskData = node.taskData else {
                logger.log("⚠️ No task data found", category: "DataManager")
                return nil
            }
            
            // Toggle the status
            let wasCompleted = taskData.status == "done"
            let newTaskData = taskData.copyWith(
                status: wasCompleted ? "todo" : "done",
                completedAt: wasCompleted ? nil : Date()
            )
            
            // Create updated node
            let updatedNode = node.copyWith(
                updatedAt: Date(),
                taskData: newTaskData
            )
            
            // Update local nodes array
            if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                nodes[index] = updatedNode
                
                // Queue for sync (unless it's a temp node)
                if !node.id.contains("-") || node.id.count != 36 {
                    await offlineQueue.queueToggleTask(nodeId: node.id, completed: !wasCompleted)
                }
                
                // Save to cache
                await cacheManager.saveNodes(nodes)

                errorMessage = "Changed offline - will sync when connected"
                
                return updatedNode
            }
            
            return nil
        }
    }

    // MARK: - Default Folder Management

    /// Gets the current default folder ID from settings
    public func getDefaultFolder() async -> String? {
        do {
            let defaultNodeId = try await api.getDefaultNode()
            return defaultNodeId
        } catch {
            logger.log("❌ Failed to get default folder: \(error)", category: "DataManager", level: .error)
            return nil
        }
    }

    /// Sets the default folder ID in settings
    public func setDefaultFolder(nodeId: String?) async -> Bool {
        do {
            try await api.setDefaultNode(nodeId: nodeId)
            return true
        } catch {
            logger.log("❌ Failed to set default folder: \(error)", category: "DataManager", level: .error)
            return false
        }
    }

    // MARK: - Template Instantiation

    /// Instantiates a template with optional parent override
    public func instantiateTemplate(templateId: String, parentId: String? = nil) async -> Node? {
        do {
            let newNode = try await api.instantiateTemplate(
                templateId: templateId,
                parentId: parentId
            )

            // Do not perform a sync or refresh here; caller handles targeted refresh/retry
            return newNode
        } catch {
            logger.log("❌ Failed to instantiate template: \(error)", category: "DataManager", level: .error)
            errorMessage = "Failed to instantiate template: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Node Refresh

    /// Refreshes a single node and its children from the API
    public func refreshNode(_ nodeId: String) async {
        // Store current state for rollback if needed
        let backupNodes = nodes
        let currentNode = nodes.first(where: { $0.id == nodeId })
        let currentChildren = nodes.filter { $0.parentId == nodeId }

        do {
            // Fetch the updated node and its direct children
            let updatedNode = try await api.getNode(id: nodeId)
            let children = try await api.getNodes(parentId: nodeId)

            // Snapshot of previous direct children
            let oldChildrenIds = Set(nodes.filter { $0.parentId == nodeId }.map { $0.id })
            let newChildrenIds = Set(children.map { $0.id })

            // Determine which direct children were removed
            let removedDirectChildren = oldChildrenIds.subtracting(newChildrenIds)

            // Helper: collect all descendant IDs for a set of parents (BFS)
            func collectDescendants(of parents: Set<String>) -> Set<String> {
                var toVisit = Array(parents)
                var descendants = Set<String>()
                // Index by parentId for O(1) child lookups
                let childrenByParent = Dictionary(grouping: nodes, by: { $0.parentId ?? "" })

                while let current = toVisit.popLast() {
                    if let kids = childrenByParent[current] {
                        for kid in kids {
                            if descendants.insert(kid.id).inserted {
                                toVisit.append(kid.id)
                            }
                        }
                    }
                }
                return descendants
            }

            // Build final removal set: removed direct children + their entire subtrees
            let removedSubtree = collectDescendants(of: removedDirectChildren)
            let idsToRemove = removedDirectChildren.union(removedSubtree)

            // 1) Remove only removed children and their descendants
            nodes.removeAll { idsToRemove.contains($0.id) }

            // 2) Upsert the main node
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[index] = updatedNode
            } else {
                nodes.append(updatedNode)
            }

            // 3) Upsert direct children returned by API (don't touch their subtrees)
            for child in children {
                if let idx = nodes.firstIndex(where: { $0.id == child.id }) {
                    nodes[idx] = child
                } else {
                    nodes.append(child)
                }
            }

        } catch {
            logger.error("❌ Failed to refresh node: \(error)", category: "DataManager")
            errorMessage = error.localizedDescription

            // Error recovery: Restore previous state to maintain consistency
            if currentNode != nil || !currentChildren.isEmpty {
                nodes = backupNodes
            }

            // If offline, the data remains consistent with last known good state
            // If network error, we've preserved consistency by rolling back
        }
    }

    // MARK: - Tag Management

    /// Search for tags by query
    public func searchTags(query: String, limit: Int = 10) async throws -> [Tag] {
        return try await api.searchTags(query: query, limit: limit)
    }

    /// Create a new tag
    public func createTag(name: String, description: String? = nil, color: String? = nil) async throws -> Tag {
        let tag = try await api.createTag(name: name, description: description, color: color)
        // Refresh tags list
        await loadTags()
        return tag
    }

    /// Attach a tag to a node
    public func attachTagToNode(nodeId: String, tagId: String) async throws {
        try await api.attachTagToNode(nodeId: nodeId, tagId: tagId)
        // Refresh the specific node to update its tags
        await refreshNode(nodeId)
    }

    /// Detach a tag from a node
    public func detachTagFromNode(nodeId: String, tagId: String) async throws {
        try await api.detachTagFromNode(nodeId: nodeId, tagId: tagId)
        // Refresh the specific node to update its tags
        await refreshNode(nodeId)
    }

    // MARK: - Node Updates

    /// Update a node with the given changes
    public func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        let updatedNode = try await api.updateNode(id: id, update: update)

        // Update the node in our local array
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index] = updatedNode
        }

        return updatedNode
    }

    /// Get a single node by ID
    public func getNode(id: String) async throws -> Node {
        // First check if we have it locally
        if let localNode = nodes.first(where: { $0.id == id }) {
            return localNode
        }

        // Otherwise fetch from API
        let node = try await api.getNode(id: id)
        return node
    }

    /// Get all rules
    public func getRules(includePublic: Bool = true, includeSystem: Bool = true) async throws -> [Rule] {
        let response = try await api.getRules(includePublic: includePublic, includeSystem: includeSystem)
        return response.rules
    }

    /// Get tags for the current account
    public func getTags() async throws -> [Tag] {
        return try await api.getTags()
    }

    /// Update a tag's name - may result in merge with existing tag
    /// Returns the updated tag and a boolean indicating if it was merged
    public func updateTag(id: String, name: String) async throws -> (tag: Tag, wasMerged: Bool) {
        let (updatedTag, wasMerged) = try await api.updateTag(id: id, name: name)

        // Refresh tags list after update
        tags = try await api.getTags()

        return (updatedTag, wasMerged)
    }

    /// Delete a tag
    public func deleteTag(id: String) async throws {
        try await api.deleteTag(id: id)

        // Refresh tags list after deletion
        tags = try await api.getTags()
    }

    // MARK: - Smart Folder Execution

    /// Executes a smart folder rule and returns the result nodes
    public func executeSmartFolder(nodeId: String) async -> [Node] {
        do {
            let resultNodes = try await api.executeSmartFolderRule(smartFolderId: nodeId)
            return resultNodes
        } catch {
            logger.log("❌ Failed to execute smart folder: \(error)", category: "DataManager", level: .error)
            errorMessage = "Failed to execute smart folder: \(error.localizedDescription)"
            return []
        }
    }
}
