import SwiftUI
import Core
import Models
import Services
import Networking
import Combine

private let logger = Logger.shared

@MainActor
public class TreeViewModel: ObservableObject, Identifiable {
    public let id = UUID()
    @Published var allNodes: [Node] = []
    @Published var nodeChildren: [String: [Node]] = [:]
    @Published var isLoading = false
    @Published var expandedNodes = Set<String>()
    @Published var selectedNodeId: String?
    @Published var focusedNodeId: String? = nil
    @Published var isEditing: Bool = false
    @Published var showingCreateDialog = false
    @Published var createNodeType = ""
    @Published var createNodeTitle = ""
    @Published var createNodeParentId: String? = nil
    @Published var showingDeleteAlert = false
    @Published var nodeToDelete: Node? = nil
    @Published var showingNoteEditorForNode: Node? = nil
    @Published var showingDetailsForNode: Node? = nil
    @Published var showingTagPickerForNode: Node? = nil
    @Published var showingHelpWindow = false

    // Drag and drop
    @Published var showingDropAlert = false
    @Published var dropAlertMessage = ""

    var dataManager: DataManager?
    private var cancellables = Set<AnyCancellable>()
    private var didLoad = false

    public init() {}
    
    func setDataManager(_ manager: DataManager) {
        logger.log("🔧 TreeViewModel.setDataManager() called", category: "TreeViewModel")
        logger.log("📊 DataManager passed in: \(String(describing: manager))", category: "TreeViewModel")
        self.dataManager = manager
        logger.log("✅ DataManager set. dataManager is now: \(self.dataManager != nil ? "NOT NIL" : "NIL")", category: "TreeViewModel")
        
        // Subscribe to DataManager's nodes changes
        manager.$nodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nodes in
                guard let self = self else { return }
                logger.log("📡 DataManager nodes changed, updating TreeViewModel", category: "TreeViewModel")
                self.updateNodesFromDataManager(nodes)
            }
            .store(in: &cancellables)
        
        logger.log("✅ DataManager set: \(dataManager != nil)", category: "TreeViewModel")
    }
    
    var currentFocusedNode: Node? {
        guard let focusedId = focusedNodeId else { return nil }
        return allNodes.first { $0.id == focusedId }
    }
    
    func getRootNodes() -> [Node] {
        logger.log("📞 getRootNodes called", category: "TreeViewModel")
        let roots = allNodes.filter { $0.parentId == nil || $0.parentId == "" }
            .sorted { $0.sortOrder < $1.sortOrder }
        logger.log("✅ Found \(roots.count) root nodes", category: "TreeViewModel")
        return roots
    }
    
    func getChildren(of nodeId: String) -> [Node] {
        logger.log("📞 getChildren called for: \(nodeId)", category: "TreeViewModel")
        let children = nodeChildren[nodeId] ?? []
        logger.log("✅ Found \(children.count) children", category: "TreeViewModel")
        return children
    }
    
    func getParentChain(for node: Node) -> [Node] {
        logger.log("📞 getParentChain called for: \(node.id)", category: "TreeViewModel")
        var chain: [Node] = []
        var currentNode: Node? = node
        
        while let current = currentNode, let parentId = current.parentId, !parentId.isEmpty {
            if let parent = allNodes.first(where: { $0.id == parentId }) {
                chain.insert(parent, at: 0)
                currentNode = parent
            } else {
                break
            }
        }
        
        logger.log("✅ Parent chain has \(chain.count) nodes", category: "TreeViewModel")
        return chain
    }
    
    private func updateNodesFromDataManager(_ nodes: [Node]) {
        logger.log("📞 updateNodesFromDataManager called with \(nodes.count) nodes", category: "TreeViewModel")
        self.allNodes = nodes

        // Preserve smart folder results before rebuilding
        var smartFolderResults: [String: [Node]] = [:]
        for (nodeId, children) in nodeChildren {
            // Check if this is a smart folder with results
            if let node = allNodes.first(where: { $0.id == nodeId }),
               node.nodeType == "smart_folder",
               !children.isEmpty {
                smartFolderResults[nodeId] = children
                logger.log("🧩 Preserving smart folder results for: \(node.title) (\(children.count) nodes)", category: "TreeViewModel")
            }
        }

        // Build parent-child relationships
        var childrenMap: [String: [Node]] = [:]
        for node in nodes {
            if let parentId = node.parentId, !parentId.isEmpty {
                if childrenMap[parentId] == nil {
                    childrenMap[parentId] = []
                }
                childrenMap[parentId]?.append(node)
            }
        }

        // Sort children by sortOrder
        for (parentId, children) in childrenMap {
            childrenMap[parentId] = children.sorted { $0.sortOrder < $1.sortOrder }
        }

        // Restore smart folder results
        for (nodeId, results) in smartFolderResults {
            childrenMap[nodeId] = results
        }

        self.nodeChildren = childrenMap
        logger.log("✅ Built parent-child relationships for \(childrenMap.count) parents", category: "TreeViewModel")
    }
    
    func loadAllNodes() async {
        guard !didLoad else {
            logger.log("⏩ Skipping loadAllNodes - already loaded", category: "TreeViewModel")
            return
        }

        logger.log("🔵 TreeViewModel.loadAllNodes() called", category: "TreeViewModel")
        isLoading = true
        didLoad = true

        await performLoad()
    }

    func refreshNodes() async {
        logger.log("🔄 TreeViewModel.refreshNodes() called - forcing refresh", category: "TreeViewModel")
        isLoading = true
        await performLoad()
    }

    private func performLoad() async {
        do {
            // Use DataManager if available, otherwise fall back to API directly
            let nodes: [Node]
            if let dataManager = dataManager {
                logger.log("✅ DataManager found, calling syncAllData()", category: "TreeViewModel")
                // Use syncAllData to load from cache when offline
                await dataManager.syncAllData()
                nodes = dataManager.nodes
                logger.log("📊 Received \(nodes.count) nodes from DataManager", category: "TreeViewModel")
            } else {
                logger.log("⚠️ No DataManager, falling back to direct API call", category: "TreeViewModel")
                nodes = try await APIClient.shared.getNodes()
                logger.log("📊 Received \(nodes.count) nodes from API directly", category: "TreeViewModel")
            }

            await MainActor.run {
                logger.log("🔄 Updating UI with \(nodes.count) nodes", category: "TreeViewModel")
                self.updateNodesFromDataManager(nodes)
                self.isLoading = false
                logger.log("✅ TreeViewModel.loadAllNodes() completed", category: "TreeViewModel")
            }
        } catch {
            logger.error("❌ Error loading nodes: \(error)", category: "TreeViewModel")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func updateSingleNode(nodeId: String) async {
        logger.log("📡 Updating single node: \(nodeId)", category: "TreeViewModel")

        do {
            // Load the updated node from API to get fresh tags
            let updatedNode = try await APIClient.shared.getNode(id: nodeId)

            await MainActor.run {
                // Find and update the node in our arrays
                if let index = self.allNodes.firstIndex(where: { $0.id == nodeId }) {
                    self.allNodes[index] = updatedNode
                    logger.log("✅ Updated node in allNodes array", category: "TreeViewModel")
                }

                // Update in parent's children list if applicable
                if let parentId = updatedNode.parentId,
                   var siblings = self.nodeChildren[parentId],
                   let childIndex = siblings.firstIndex(where: { $0.id == nodeId }) {
                    siblings[childIndex] = updatedNode
                    self.nodeChildren[parentId] = siblings
                    logger.log("✅ Updated node in parent's children list", category: "TreeViewModel")
                }

                // Update in DataManager if available
                if let dataManager = self.dataManager,
                   let dmIndex = dataManager.nodes.firstIndex(where: { $0.id == nodeId }) {
                    dataManager.nodes[dmIndex] = updatedNode
                    logger.log("✅ Updated node in DataManager", category: "TreeViewModel")
                }
            }
        } catch {
            logger.error("❌ Failed to update single node: \(error)", category: "TreeViewModel")
        }
    }
    
    func deleteNode(_ node: Node) {
        logger.log("📞 deleteNode called for: \(node.id) - \(node.title)", category: "TreeViewModel")
        nodeToDelete = node
        showingDeleteAlert = true
        logger.log("🔄 Delete alert shown", category: "TreeViewModel")
    }
    
    func confirmDeleteNode() async {
        logger.log("📞 confirmDeleteNode called", category: "TreeViewModel")
        guard let node = nodeToDelete, let dataManager = dataManager else {
            logger.log("❌ No node to delete or no dataManager", category: "TreeViewModel")
            return
        }
        logger.log("📞 Deleting node: \(node.id) - \(node.title)", category: "TreeViewModel")

        logger.log("📞 Confirming delete for node: \(node.id) - \(node.title)", category: "TreeViewModel")

        // Before deletion, find the next node to select
        var nextSelectionId: String? = nil

        // If this node was selected, find what to select next
        if selectedNodeId == node.id {
            // Find siblings of the node being deleted
            let siblings: [Node]
            if let parentId = node.parentId {
                // Node has a parent, get its siblings
                siblings = nodeChildren[parentId]?.sorted { $0.sortOrder < $1.sortOrder } ?? []
            } else {
                // Root node, get root siblings
                siblings = getRootNodes()
            }

            if let currentIndex = siblings.firstIndex(where: { $0.id == node.id }) {
                // Try to select previous sibling
                if currentIndex > 0 {
                    nextSelectionId = siblings[currentIndex - 1].id
                    logger.log("📍 Will select previous sibling: \(siblings[currentIndex - 1].title)", category: "TreeViewModel")
                }
                // If no previous, try next sibling
                else if currentIndex < siblings.count - 1 {
                    nextSelectionId = siblings[currentIndex + 1].id
                    logger.log("📍 Will select next sibling: \(siblings[currentIndex + 1].title)", category: "TreeViewModel")
                }
                // No siblings, selection will be nil
                else {
                    logger.log("📍 No siblings to select after deletion", category: "TreeViewModel")
                }
            }
        }

        // Collect all nodes to delete (node and its descendants)
        var nodesToRemove = Set<String>()
        nodesToRemove.insert(node.id)

        // Find all descendants
        func findDescendants(of nodeId: String) {
            if let children = nodeChildren[nodeId] {
                for child in children {
                    nodesToRemove.insert(child.id)
                    findDescendants(of: child.id)
                }
            }
        }
        findDescendants(of: node.id)

        logger.log("🗑️ Will delete \(nodesToRemove.count) nodes total", category: "TreeViewModel")

        // Delete from backend - DataManager will update its nodes array which triggers our subscription
        await dataManager.deleteNode(node)

        // Handle UI-specific state cleanup and selection
        await MainActor.run {
            // If we were focused on a deleted node, unfocus
            if let focusedId = self.focusedNodeId, nodesToRemove.contains(focusedId) {
                self.focusedNodeId = nil
            }

            // Set the new selection
            self.selectedNodeId = nextSelectionId

            // Clear the nodeToDelete
            self.nodeToDelete = nil

            logger.log("✅ Delete completed, selected node: \(nextSelectionId ?? "none")", category: "TreeViewModel")
        }
    }
    
    func toggleTaskStatus(_ node: Node) {
        logger.log("📞 toggleTaskStatus called with node: \(node.id) - \(node.title)", category: "TreeViewModel")
        logger.log("DataManager available: \(dataManager != nil)", category: "TreeViewModel")
        
        guard let dataManager = dataManager else { 
            logger.error("❌ No dataManager available - THIS IS THE PROBLEM!", category: "TreeViewModel")
            return 
        }
        
        logger.log("Creating Task to call DataManager", category: "TreeViewModel")
        
        Task {
            logger.log("Inside Task, calling dataManager.toggleNodeCompletion", category: "TreeViewModel")
            // Update backend - the DataManager subscription will handle the UI update
            if let updatedNode = await dataManager.toggleNodeCompletion(node) {
                logger.log("✅ Received updated node from DataManager", category: "TreeViewModel")
                // The subscription to DataManager.nodes will automatically update our view
            } else {
                logger.error("❌ toggleNodeCompletion returned nil", category: "TreeViewModel")
            }
        }
    }
    
    func updateNodeTitle(nodeId: String, newTitle: String) async {
        guard let dataManager = dataManager else {
            logger.log("❌ No dataManager available", category: "TreeViewModel")
            return
        }

        guard let nodeIndex = allNodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.log("❌ Node not found: \(nodeId)", category: "TreeViewModel")
            return
        }

        let node = allNodes[nodeIndex]
        logger.log("📝 Updating node title - id: \(nodeId), newTitle: \(newTitle)", category: "TreeViewModel")

        // Create update object with new title
        let update = NodeUpdate(
            title: newTitle,
            parentId: node.parentId,
            sortOrder: node.sortOrder,
            noteData: node.noteData.map { NoteDataUpdate(body: $0.body) }
        )

        // Update via DataManager (handles both online and offline scenarios)
        if let updatedNode = await dataManager.updateNode(nodeId, update: update) {
            logger.log("✅ Node title updated successfully: \(updatedNode.title)", category: "TreeViewModel")

            // Update the local node array directly instead of reloading everything
            // Note: DataManager already updates its nodes array, which triggers our subscription
            // So this local update might be redundant, but ensures immediate UI feedback
            await MainActor.run {
                self.allNodes[nodeIndex] = updatedNode

                // If the node is in a parent's children list, update that too
                if let parentId = updatedNode.parentId {
                    if var siblings = self.nodeChildren[parentId] {
                        if let childIndex = siblings.firstIndex(where: { $0.id == nodeId }) {
                            siblings[childIndex] = updatedNode
                            self.nodeChildren[parentId] = siblings
                        }
                    }
                }
            }
        } else {
            logger.log("⚠️ Node update returned nil - might be offline and queued", category: "TreeViewModel")
            // In offline mode, the update is queued but we don't get an updated node back
            // For now, we could show a temporary local update for better UX
            // Offline feedback is handled by DataManager's queue
        }
    }

    // MARK: - Drag and Drop

    func performReorder(draggedNode: Node, targetNode: Node, position: DropPosition, message: String) async {
        // Don't show alert anymore, just log
        logger.log("🎯 Reordering nodes: \(message)", category: "TreeViewModel")

        // Get all siblings
        let siblings: [Node]
        if let parentId = draggedNode.parentId {
            siblings = nodeChildren[parentId] ?? []
        } else {
            // Root nodes
            siblings = getRootNodes()
        }

        // Create a mutable array for reordering
        var orderedSiblings = siblings

        // Find current positions
        guard let draggedIndex = orderedSiblings.firstIndex(where: { $0.id == draggedNode.id }),
              let targetIndex = orderedSiblings.firstIndex(where: { $0.id == targetNode.id }) else {
            logger.log("❌ Could not find nodes in siblings array", category: "TreeViewModel")
            return
        }

        // Remove the dragged node
        orderedSiblings.remove(at: draggedIndex)

        // Calculate new insertion index based on position
        let insertIndex: Int
        if position == .above {
            // Insert before target
            insertIndex = targetIndex > draggedIndex ? targetIndex - 1 : targetIndex
        } else {
            // Insert after target
            insertIndex = targetIndex >= draggedIndex ? targetIndex : targetIndex + 1
        }

        // Insert at new position
        orderedSiblings.insert(draggedNode, at: insertIndex)

        // Now recalculate sort orders
        // We'll use increments of 100 to leave room for future insertions
        var updates: [(nodeId: String, sortOrder: Int)] = []
        for (index, node) in orderedSiblings.enumerated() {
            let newSortOrder = (index + 1) * 100
            if node.sortOrder != newSortOrder {
                updates.append((nodeId: node.id, sortOrder: newSortOrder))
                logger.log("📝 Node '\(node.title)' will get sort order \(newSortOrder)", category: "TreeViewModel")
            }
        }

        // Send updates to backend
        guard let dataManager = dataManager else {
            logger.log("❌ No dataManager available", category: "TreeViewModel")
            return
        }

        // Update each node's sort order
        for update in updates {
            if let nodeIndex = allNodes.firstIndex(where: { $0.id == update.nodeId }) {
                let node = allNodes[nodeIndex]

                let nodeUpdate = NodeUpdate(
                    title: node.title,
                    parentId: node.parentId,
                    sortOrder: update.sortOrder,
                    noteData: node.noteData.map { NoteDataUpdate(body: $0.body) }
                )

                // This will update the backend and trigger a refresh
                _ = await dataManager.updateNode(node.id, update: nodeUpdate)
            }
        }

        logger.log("✅ Reordering complete, updated \(updates.count) nodes", category: "TreeViewModel")
    }

    func showDropAlert(message: String) {
        dropAlertMessage = message
        showingDropAlert = true
        logger.log("🎯 Showing drop alert: \(dropAlertMessage)", category: "TreeViewModel")
    }

    func createNode(type: String, title: String, parentId: String?) async {
        guard let dataManager = dataManager else { 
            logger.log("❌ No dataManager available", category: "TreeViewModel")
            return 
        }
        
        logger.log("📞 Creating node - type: \(type), title: \(title), parentId: \(parentId ?? "nil")", category: "TreeViewModel")
        
        if let createdNode = await dataManager.createNode(
            title: title,
            type: type,
            content: nil,
            parentId: parentId,
            tags: []
        ) {
            logger.log("✅ Node created successfully: \(createdNode.id)", category: "TreeViewModel")
            
            // The DataManager subscription will update allNodes and nodeChildren automatically
            // We only need to expand the parent if needed
            await MainActor.run {
                if let parentId = createdNode.parentId {
                    // Expand parent to show the new node
                    self.expandedNodes.insert(parentId)
                }
            }
        } else {
            logger.log("❌ Failed to create node", category: "TreeViewModel")
        }
    }

    // MARK: - Template Instantiation

    func instantiateTemplate(_ template: Node) async {
        logger.log("📞 Instantiating template: \(template.title)", category: "TreeViewModel")

        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let dateString = dateFormatter.string(from: Date())
            let name = "\(template.title) - \(dateString)"

            // Use the template's target node if it has one
            let targetNodeId = template.templateData?.targetNodeId

            let api = APIClient.shared
            let newNode = try await api.instantiateTemplate(
                templateId: template.id,
                name: name,
                parentId: targetNodeId  // Pass the target node to the API
            )

            logger.log("✅ Template instantiated successfully: \(newNode.title)", category: "TreeViewModel")

            // Do a full tree refresh to capture everything
            await refreshNodes()

            // After refresh, expand target node and focus the new node
            await MainActor.run {
                // Expand the target node if it exists
                if let targetId = targetNodeId {
                    self.expandedNodes.insert(targetId)
                }

                // Select and focus the newly created node
                self.selectedNodeId = newNode.id
                self.focusedNodeId = newNode.id
            }
        } catch {
            logger.log("❌ Failed to instantiate template: \(error)", level: .error, category: "TreeViewModel")
        }
    }

}