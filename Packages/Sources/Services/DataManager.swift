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
        logger.log("📞 Initializing DataManager", category: "DataManager")
        logger.log("✅ DataManager initialized with APIClient", category: "DataManager")
        
        // Monitor network status - handle both NetworkMonitor and TestableNetworkMonitor
        if let observableMonitor = networkMonitor as? NetworkMonitor {
            observableMonitor.$isConnected
                .sink { [weak self] isConnected in
                    guard let self = self else { return }
                    
                    let wasOffline = self.isOffline
                    self.isOffline = !isConnected
                    
                    if isConnected {
                        logger.log("📡 DataManager: Network is available", category: "DataManager")
                        
                        // Trigger auto-sync if coming back online with pending operations
                        if wasOffline && !self.offlineQueue.pendingOperations.isEmpty {
                            logger.log("🔄 Network restored - triggering auto-sync of pending operations", category: "DataManager")
                            self.syncTask = Task {
                                await self.syncPendingOperations()
                            }
                        }
                    } else {
                        logger.log("📡 DataManager: Network is unavailable", category: "DataManager")
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
                        logger.log("📡 [TEST] DataManager: Network is available", category: "DataManager")
                        
                        // Trigger auto-sync if coming back online with pending operations
                        if wasOffline && !self.offlineQueue.pendingOperations.isEmpty {
                            logger.log("🔄 [TEST] Network restored - triggering auto-sync of pending operations", category: "DataManager")
                            self.syncTask = Task {
                                await self.syncPendingOperations()
                            }
                        }
                    } else {
                        logger.log("📡 [TEST] DataManager: Network is unavailable", category: "DataManager")
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    public func loadNodes(parentId: String? = nil) async {
        logger.log("📞 Starting to load nodes, parentId: \(parentId ?? "nil")", category: "DataManager")
        isLoading = true
        errorMessage = nil
        
        do {
            logger.log("📞 Calling API to get nodes", category: "DataManager")
            nodes = try await api.getNodes(parentId: parentId)
            logger.log("✅ Successfully loaded \(nodes.count) nodes", category: "DataManager")
            
            // Log node types for debugging
            let nodeTypes = Dictionary(grouping: nodes, by: { $0.nodeType })
            for (type, typeNodes) in nodeTypes {
                logger.log("   - \(type): \(typeNodes.count) nodes", category: "DataManager")
            }
        } catch {
            logger.log("❌ Failed to load nodes: \(error)", category: "DataManager")
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
        logger.log("✅ Load nodes completed, isLoading set to false", category: "DataManager")
    }
    
    public func loadTags() async {
        logger.log("📞 Starting to load tags", category: "DataManager")
        do {
            logger.log("📞 Calling API to get tags", category: "DataManager")
            tags = try await api.getTags()
            logger.log("✅ Successfully loaded \(tags.count) tags", category: "DataManager")
        } catch {
            logger.log("❌ Failed to load tags: \(error)", category: "DataManager")
            errorMessage = error.localizedDescription
        }
    }
    
    public func createNode(title: String, type: String, content: String? = nil, parentId: String? = nil, tags: [Tag]? = nil) async -> Node? {
        logger.log("📞 createNode called with title: '\(title)', type: '\(type)', parentId: \(parentId ?? "nil")", category: "DataManager")
        
        if networkMonitor.isConnected {
            // Online - create via API
            do {
                let createdNode: Node
                
                switch type {
                case "folder":
                    createdNode = try await api.createFolder(title: title, parentId: parentId)
                case "task":
                    createdNode = try await api.createTask(title: title, parentId: parentId, description: content)
                case "note":
                    createdNode = try await api.createNote(title: title, parentId: parentId, body: content ?? "")
                case "template", "smart_folder":
                    // Use generic node creation with the actual type
                    logger.log("📞 Creating \(type) node", category: "DataManager")
                    createdNode = try await api.createGenericNode(title: title, nodeType: type, parentId: parentId)
                default:
                    logger.log("❌ Unknown node type: \(type)", category: "DataManager")
                    errorMessage = "Unknown node type: \(type)"
                    return nil
                }
                
                // Add to local nodes array and update cache in one go
                nodes.append(createdNode)
                nodes.sort { $0.sortOrder < $1.sortOrder }
                logger.log("✅ Created node: \(createdNode.title) (id: \(createdNode.id))", category: "DataManager")
                
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
            logger.log("📴 Offline - creating node locally", category: "DataManager")
            
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
            
            logger.log("✅ Created node locally: \(newNode.title) (temp id: \(tempId))", category: "DataManager")
            errorMessage = "Created offline - will sync when connected"
            
            return newNode
        }
    }
    
    public func updateNode(_ nodeId: String, update: NodeUpdate) async -> Node? {
        logger.log("📞 updateNode called with id: \(nodeId), title: '\(update.title)'", category: "DataManager")

        // Find the node to update
        guard let nodeIndex = nodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.log("❌ Node not found: \(nodeId)", category: "DataManager")
            return nil
        }

        let oldNode = nodes[nodeIndex]

        if networkMonitor.isConnected {
            // Online - update via API
            do {
                logger.log("📞 Calling API to update node", category: "DataManager")
                let updatedNode = try await api.updateNode(id: nodeId, update: update)
                logger.log("✅ API call successful", category: "DataManager")

                // Clear any previous error on success
                errorMessage = nil

                // Update local array
                nodes[nodeIndex] = updatedNode
                logger.log("✅ Updated node in local array", category: "DataManager")

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
            logger.log("📵 Offline - queueing update operation", category: "DataManager")

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
                smartFolderData: oldNode.smartFolderData  // Smart folder data preserved from original
            )

            // Update local array optimistically
            nodes[nodeIndex] = updatedNode

            // Update cache with optimistic change
            await cacheManager.saveNodes(nodes)

            logger.log("✅ Update operation queued for offline sync with optimistic update", category: "DataManager")

            return updatedNode
        }
    }
    
    public func deleteNode(_ node: Node) async {
        logger.log("📞 deleteNode called with node: \(node.id) - '\(node.title)'", category: "DataManager")
        
        if networkMonitor.isConnected {
            // Online - delete via API
            do {
                logger.log("📞 Calling API to delete node", category: "DataManager")
                try await api.deleteNode(id: node.id)
                logger.log("✅ API call successful", category: "DataManager")
                
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
                logger.log("✅ Removed \(nodesToRemove.count) nodes from local array (count: \(oldCount) -> \(newCount))", category: "DataManager")
                
                // Update cache
                await cacheManager.saveNodes(nodes)
            } catch {
                logger.log("❌ Failed to delete node: \(error)", category: "DataManager")
                errorMessage = error.localizedDescription
            }
        } else {
            // Offline - delete locally and queue for sync
            logger.log("📴 Offline - deleting node locally", category: "DataManager")
            
            // Queue for sync (unless it's a temp node that was created offline)
            if !node.id.hasPrefix("temp-") {
                // This is a real server node, queue the deletion
                await offlineQueue.queueDelete(nodeId: node.id, title: node.title)
            } else {
                // This was created offline - remove it from create queue instead
                logger.log("🗑️ Removing offline-created node from queue", category: "DataManager")
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
            
            logger.log("✅ Deleted node locally: \(node.title)", category: "DataManager")
            errorMessage = "Deleted offline - will sync when connected"
        }
    }
    
    /// Perform a full sync of all user data
    public func syncAllData() async {
        logger.log("🔄 DataManager.syncAllData() called", category: "DataManager")
        logger.log("📊 Current state: isConnected=\(networkMonitor.isConnected), nodes.count=\(nodes.count)", category: "DataManager")
        isLoading = true
        errorMessage = nil
        
        if networkMonitor.isConnected {
            logger.log("🌐 Network is CONNECTED - will fetch from API", category: "DataManager")
            // Online - fetch from API and cache
            do {
                // Fetch ALL data
                logger.log("📡 Calling api.getAllNodes() and api.getTags()", category: "DataManager")
                
                async let fetchedNodes = api.getAllNodes()
                async let fetchedTags = api.getTags()
                // Rules will be added when API supports them
                
                let (allNodes, allTags) = try await (fetchedNodes, fetchedTags)
                
                logger.log("✅ API returned: \(allNodes.count) nodes, \(allTags.count) tags", category: "DataManager")
                
                // SAFETY CHECK: Don't wipe data if server returns empty when we had data
                if allNodes.isEmpty && !nodes.isEmpty {
                    logger.log("⚠️ Server returned empty nodes but we have \(nodes.count) cached - keeping cache", level: .warning, category: "DataManager")
                    errorMessage = "Server returned no data - using cache"
                    await loadFromCache()
                    isLoading = false
                    return
                }
                
                // Update local state
                logger.log("📝 Updating local state with fetched data", category: "DataManager")
                self.nodes = allNodes
                self.tags = allTags
                
                // Save to cache
                logger.log("💾 Saving to cache...", category: "DataManager")
                await cacheManager.saveNodes(allNodes)
                await cacheManager.saveTags(allTags)
                await cacheManager.saveMetadata(
                    nodeCount: allNodes.count,
                    tagCount: allTags.count,
                    ruleCount: 0  // Will be updated when rules are supported
                )
                
                self.lastSyncDate = Date()
                logger.log("✅ Data sync completed successfully", category: "DataManager")
                
            } catch {
                logger.log("❌ API call failed with error: \(error)", level: .error, category: "DataManager")
                logger.log("📊 Error details: \(error.localizedDescription)", level: .error, category: "DataManager")
                errorMessage = "Sync failed. Loading from cache..."
                
                // Fall back to cache
                logger.log("🔄 Falling back to cache...", category: "DataManager")
                await loadFromCache()
            }
        } else {
            // Offline - load from cache
            logger.log("📴 Network is OFFLINE - loading from cache", category: "DataManager")
            await loadFromCache()
        }
        
        isLoading = false
        logger.log("✅ DataManager.syncAllData() completed. Final nodes.count=\(nodes.count)", category: "DataManager")
    }
    
    /// Sync pending offline operations
    public func syncPendingOperations() async {
        logger.log("🔄 Starting sync of pending operations", category: "DataManager")

        // Cancel any existing sync task to prevent duplicates
        if let existingTask = syncTask, !existingTask.isCancelled {
            logger.log("⚠️ Cancelling existing sync task to prevent duplicates", category: "DataManager")
            existingTask.cancel()
        }

        // Add delay to debounce rapid network changes (like subway WiFi)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

        // Check if cancelled during delay
        if Task.isCancelled {
            logger.log("🚫 Sync cancelled during debounce delay", category: "DataManager")
            return
        }

        // Process the queue
        let (succeeded, failed, tempIdMap) = await offlineQueue.processPendingOperations()
        
        if succeeded > 0 || failed > 0 {
            logger.log("📊 Sync results: \(succeeded) succeeded, \(failed) failed", category: "DataManager")
            
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
        logger.log("🔄 Replacing \(tempIdMap.count) temporary IDs", category: "DataManager")
        
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
                logger.log("✅ Replaced temp ID \(tempId) with server ID \(serverId)", category: "DataManager")
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
        logger.log("📦 DataManager.loadFromCache() called", category: "DataManager")
        
        if let cachedNodes = await cacheManager.loadNodes() {
            self.nodes = cachedNodes
            logger.log("✅ Loaded \(cachedNodes.count) nodes from cache", category: "DataManager")
        } else {
            logger.log("⚠️ No nodes found in cache", category: "DataManager")
        }
        
        if let cachedTags = await cacheManager.loadTags() {
            self.tags = cachedTags
            logger.log("✅ Loaded \(cachedTags.count) tags from cache", category: "DataManager")
        } else {
            logger.log("⚠️ No tags found in cache", category: "DataManager")
        }
        
        if let metadata = await cacheManager.loadMetadata() {
            self.lastSyncDate = metadata.lastSyncDate
            logger.log("📅 Cache last synced: \(metadata.lastSyncDate)", category: "DataManager")
        } else {
            logger.log("⚠️ No cache metadata found", category: "DataManager")
        }
        
        logger.log("✅ DataManager.loadFromCache() completed. nodes.count=\(nodes.count)", category: "DataManager")
    }
    
    public func toggleNodeCompletion(_ node: Node) async -> Node? {
        logger.log("📞 toggleNodeCompletion called with node: \(node.id) - '\(node.title)'", category: "DataManager")
        logger.log("   - Node type: \(node.nodeType)", category: "DataManager")
        logger.log("   - Current completion: \(node.taskData?.completedAt != nil)", category: "DataManager")
        
        guard node.nodeType == "task" else {
            logger.log("⚠️ Not a task node, returning nil", category: "DataManager")
            return nil
        }
        
        if networkMonitor.isConnected {
            // Online - toggle via API
            do {
                let isCurrentlyCompleted = node.taskData?.status == "done"
                logger.log("📞 Calling API.toggleTaskCompletion", category: "DataManager")
                logger.log("   - Node ID: \(node.id)", category: "DataManager")
                logger.log("   - Currently completed: \(isCurrentlyCompleted)", category: "DataManager")
                
                let updatedNode = try await api.toggleTaskCompletion(
                    nodeId: node.id,
                    currentlyCompleted: isCurrentlyCompleted
                )
                
                logger.log("✅ API call successful", category: "DataManager")
                logger.log("   - Updated completion: \(updatedNode.taskData?.status == "done")", category: "DataManager")
                
                // Clear any previous error on success
                errorMessage = nil
                
                // Update local nodes array
                if let index = nodes.firstIndex(where: { $0.id == node.id }) {
                    nodes[index] = updatedNode
                    logger.log("✅ Updated local nodes array at index \(index)", category: "DataManager")
                    
                    // Update cache
                    await cacheManager.saveNodes(nodes)
                } else {
                    logger.log("⚠️ Node not found in local nodes array", category: "DataManager")
                }
                
                logger.log("✅ Toggled task completion for: \(node.title) - now \(isCurrentlyCompleted ? "uncompleted" : "completed")", category: "DataManager")
                return updatedNode
            } catch {
                logger.log("❌ Failed to toggle task completion: \(error)", category: "DataManager")
                logger.log("   - Error type: \(type(of: error))", category: "DataManager")
                logger.log("   - Error description: \(error.localizedDescription)", category: "DataManager")
                errorMessage = error.localizedDescription
                return nil
            }
        } else {
            // Offline - toggle locally and queue for sync
            logger.log("📴 Offline - toggling task locally", category: "DataManager")
            
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
                
                logger.log("✅ Toggled task locally: \(node.title) - now \(!wasCompleted ? "completed" : "uncompleted")", category: "DataManager")
                errorMessage = "Changed offline - will sync when connected"
                
                return updatedNode
            }
            
            return nil
        }
    }

    // MARK: - Default Folder Management

    /// Gets the current default folder ID from settings
    public func getDefaultFolder() async -> String? {
        logger.log("📞 getDefaultFolder called", category: "DataManager")

        do {
            let defaultNodeId = try await api.getDefaultNode()
            logger.log("✅ Got default folder: \(defaultNodeId ?? "none")", category: "DataManager")
            return defaultNodeId
        } catch {
            logger.log("❌ Failed to get default folder: \(error)", level: .error, category: "DataManager")
            return nil
        }
    }

    /// Sets the default folder ID in settings
    public func setDefaultFolder(nodeId: String?) async -> Bool {
        logger.log("📞 setDefaultFolder called with nodeId: \(nodeId ?? "nil")", category: "DataManager")

        do {
            try await api.setDefaultNode(nodeId: nodeId)
            logger.log("✅ Set default folder to: \(nodeId ?? "none")", category: "DataManager")
            return true
        } catch {
            logger.log("❌ Failed to set default folder: \(error)", level: .error, category: "DataManager")
            return false
        }
    }

    // MARK: - Template Instantiation

    /// Instantiates a template with optional parent override
    public func instantiateTemplate(templateId: String, parentId: String? = nil) async -> Node? {
        logger.log("📞 instantiateTemplate called", category: "DataManager")
        logger.log("   Template ID: \(templateId)", category: "DataManager")
        logger.log("   Parent ID: \(parentId ?? "nil")", category: "DataManager")

        do {
            let newNode = try await api.instantiateTemplate(
                templateId: templateId,
                parentId: parentId
            )

            logger.log("✅ Template instantiated successfully", category: "DataManager")
            logger.log("   New node ID: \(newNode.id)", category: "DataManager")
            logger.log("   New node title: \(newNode.title)", category: "DataManager")

            // Refresh nodes to include the new one
            await syncAllData()

            return newNode
        } catch {
            logger.log("❌ Failed to instantiate template: \(error)", level: .error, category: "DataManager")
            errorMessage = "Failed to instantiate template: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Node Refresh

    /// Refreshes a single node from the API
    public func refreshNode(_ nodeId: String) async {
        logger.log("📞 refreshNode called for: \(nodeId)", category: "DataManager")

        do {
            let updatedNode = try await api.getNode(id: nodeId)

            // Update the node in our nodes array
            if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[index] = updatedNode
                logger.log("✅ Node refreshed: \(updatedNode.title)", category: "DataManager")
            } else {
                // Node not found locally, add it
                nodes.append(updatedNode)
                logger.log("✅ Node added: \(updatedNode.title)", category: "DataManager")
            }
        } catch {
            logger.error("❌ Failed to refresh node: \(error)", category: "DataManager")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Tag Management

    /// Search for tags by query
    public func searchTags(query: String, limit: Int = 10) async throws -> [Tag] {
        logger.log("📞 searchTags called with query: \(query)", category: "DataManager")
        return try await api.searchTags(query: query, limit: limit)
    }

    /// Create a new tag
    public func createTag(name: String, description: String? = nil, color: String? = nil) async throws -> Tag {
        logger.log("📞 createTag called with name: \(name)", category: "DataManager")
        let tag = try await api.createTag(name: name, description: description, color: color)
        // Refresh tags list
        await loadTags()
        return tag
    }

    /// Attach a tag to a node
    public func attachTagToNode(nodeId: String, tagId: String) async throws {
        logger.log("📞 attachTagToNode called - node: \(nodeId), tag: \(tagId)", category: "DataManager")
        try await api.attachTagToNode(nodeId: nodeId, tagId: tagId)
        // Refresh the specific node to update its tags
        await refreshNode(nodeId)
    }

    /// Detach a tag from a node
    public func detachTagFromNode(nodeId: String, tagId: String) async throws {
        logger.log("📞 detachTagFromNode called - node: \(nodeId), tag: \(tagId)", category: "DataManager")
        try await api.detachTagFromNode(nodeId: nodeId, tagId: tagId)
        // Refresh the specific node to update its tags
        await refreshNode(nodeId)
    }

    // MARK: - Node Updates

    /// Update a node with the given changes
    public func updateNode(id: String, update: NodeUpdate) async throws -> Node {
        logger.log("📞 updateNode called for id: \(id)", category: "DataManager")
        let updatedNode = try await api.updateNode(id: id, update: update)

        // Update the node in our local array
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index] = updatedNode
            logger.log("✅ Node updated locally: \(updatedNode.title)", category: "DataManager")
        }

        return updatedNode
    }

    /// Get a single node by ID
    public func getNode(id: String) async throws -> Node {
        logger.log("📞 getNode called for id: \(id)", category: "DataManager")

        // First check if we have it locally
        if let localNode = nodes.first(where: { $0.id == id }) {
            logger.log("✅ Found node locally: \(localNode.title)", category: "DataManager")
            return localNode
        }

        // Otherwise fetch from API
        let node = try await api.getNode(id: id)
        logger.log("✅ Fetched node from API: \(node.title)", category: "DataManager")
        return node
    }

    /// Get all rules
    public func getRules(includePublic: Bool = true, includeSystem: Bool = true) async throws -> [Rule] {
        logger.log("📞 getRules called", category: "DataManager")
        let response = try await api.getRules(includePublic: includePublic, includeSystem: includeSystem)
        return response.rules
    }

    /// Get tags for the current account
    public func getTags() async throws -> [Tag] {
        logger.log("📞 getTags called", category: "DataManager")
        return try await api.getTags()
    }

    // MARK: - Smart Folder Execution

    /// Executes a smart folder rule and returns the result nodes
    public func executeSmartFolder(nodeId: String) async -> [Node] {
        logger.log("📞 executeSmartFolder called for node: \(nodeId)", category: "DataManager")

        do {
            let resultNodes = try await api.executeSmartFolderRule(smartFolderId: nodeId)

            logger.log("✅ Smart folder executed successfully", category: "DataManager")
            logger.log("   Returned \(resultNodes.count) nodes", category: "DataManager")

            // Log first few results for debugging
            for (index, node) in resultNodes.prefix(3).enumerated() {
                logger.log("   Result \(index + 1): \(node.title) (type: \(node.nodeType))", category: "DataManager")
            }
            if resultNodes.count > 3 {
                logger.log("   ... and \(resultNodes.count - 3) more nodes", category: "DataManager")
            }

            return resultNodes
        } catch {
            logger.log("❌ Failed to execute smart folder: \(error)", level: .error, category: "DataManager")
            errorMessage = "Failed to execute smart folder: \(error.localizedDescription)"
            return []
        }
    }
}
