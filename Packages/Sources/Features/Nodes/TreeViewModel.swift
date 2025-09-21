import SwiftUI
import Core
import Models
import Services
import Combine
#if os(macOS)
import AppKit
#endif

private let logger = Logger.shared

@MainActor
public class TreeViewModel: ObservableObject, Identifiable {
    public let id = UUID()
    // allNodes is now a computed property from DataManager
    var allNodes: [Node] {
        dataManager?.nodes ?? []
    }
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
        // No need to set allNodes anymore, it's computed from dataManager

        // Preserve smart folder results before rebuilding
        var smartFolderResults: [String: [Node]] = [:]
        for (nodeId, children) in nodeChildren {
            // Check if this is a smart folder with results
            // Use the nodes parameter instead of allNodes to ensure we have the data
            if let node = nodes.first(where: { $0.id == nodeId }),
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
    
    /// Initial load of nodes - only runs once per view lifecycle
    func initialLoad() async {
        guard !didLoad else {
            logger.log("⏩ Skipping initialLoad - already loaded", category: "TreeViewModel")
            return
        }

        logger.log("🔵 TreeViewModel.initialLoad() called - first time load", category: "TreeViewModel")
        isLoading = true
        didLoad = true

        await performLoad()
    }

    /// Force a full refresh of all nodes from the server
    func refreshNodes() async {
        logger.log("🔄 TreeViewModel.refreshNodes() called - forcing full refresh", category: "TreeViewModel")
        isLoading = true

        // Always use DataManager for refresh to ensure consistency
        if let dataManager = dataManager {
            await dataManager.syncAllData()
            // DataManager will update its nodes property which we're subscribed to
            isLoading = false
        } else {
            await performLoad()
        }
    }

    /// Refresh a specific node and its children
    func refreshNode(nodeId: String) async {
        logger.log("🔄 Refreshing single node: \(nodeId)", category: "TreeViewModel")

        guard let dataManager = dataManager else {
            logger.error("❌ No DataManager available for single node refresh", category: "TreeViewModel")
            return
        }

        // Use DataManager to refresh the single node
        await dataManager.refreshNode(nodeId)
    }

    private func performLoad() async {
        do {
            // Use DataManager if available, otherwise fall back to API directly
            let nodes: [Node]
            guard let dataManager = dataManager else {
                logger.error("❌ No DataManager available - cannot load nodes", category: "TreeViewModel")
                return // Early return, no error throw needed as this is caught in the do-catch
            }

            logger.log("✅ DataManager found, calling syncAllData()", category: "TreeViewModel")
            // Use syncAllData to load from cache when offline
            await dataManager.syncAllData()
            nodes = dataManager.nodes
            logger.log("📊 Received \(nodes.count) nodes from DataManager", category: "TreeViewModel")

            await MainActor.run {
                logger.log("🔄 Updating UI with \(nodes.count) nodes", category: "TreeViewModel")
                self.updateNodesFromDataManager(nodes)
                self.isLoading = false
                logger.log("✅ TreeViewModel.performLoad() completed", category: "TreeViewModel")
            }
        } catch {
            logger.error("❌ Error loading nodes: \(error)", category: "TreeViewModel")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func updateSingleNode(nodeId: String) async {
        // Delegate to refreshNode for consistency
        await refreshNode(nodeId: nodeId)
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

        guard let node = allNodes.first(where: { $0.id == nodeId }) else {
            logger.log("❌ Node not found: \(nodeId)", category: "TreeViewModel")
            return
        }

        logger.log("📝 Updating node title - id: \(nodeId), newTitle: \(newTitle)", category: "TreeViewModel")

        // Create update object with new title
        let update = NodeUpdate(
            title: newTitle,
            parentId: node.parentId,
            sortOrder: node.sortOrder,
            noteData: node.noteData.map { NoteDataUpdate(body: $0.body) }
        )

        // Update via DataManager (handles both online and offline scenarios)
        // DataManager will update its nodes array, which triggers our subscription
        // and automatically updates our view through updateNodesFromDataManager
        if let updatedNode = await dataManager.updateNode(nodeId, update: update) {
            logger.log("✅ Node title updated successfully: \(updatedNode.title)", category: "TreeViewModel")
            // The subscription to DataManager.nodes will handle all UI updates
        } else {
            logger.log("⚠️ Node update returned nil - might be offline and queued", category: "TreeViewModel")
            // In offline mode, the update is queued and DataManager handles local updates
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

    // MARK: - UI Intent Methods

    /// Centralized keyboard event handling
    func handleKeyPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        logger.log("⌨️ handleKeyPress - keyCode: \(keyCode), modifiers: \(modifiers)", category: "TreeViewModel")

        // Handle Command key combinations
        if modifiers.contains(.command) {
            switch keyCode {
            case 8: // C - Copy node names
                if showingNoteEditorForNode != nil {
                    return false  // Let note editor handle it
                }
                performAction(.copyNodeNames)
                return true

            case 2: // D - Details or Delete
                if modifiers.contains(.shift) {
                    performAction(.deleteNode)
                } else {
                    performAction(.showDetails)
                }
                return true

            case 3: // F - Focus
                if modifiers.contains(.shift) {
                    performAction(.focusNode)
                    return true
                }
                break

            case 17: // T - Tags
                performAction(.showTags)
                return true

            case 14: // E - Execute smart folder
                performAction(.executeSmartFolder)
                return true

            case 32: // U - Use template
                performAction(.useTemplate)
                return true

            case 12: // Q - Quick task
                Task { await performAction(.createQuickTask) }
                return true

            default:
                break
            }
        }

        // Handle non-command shortcuts
        switch keyCode {
        case 3: // F - unfocus (when no command modifier)
            if !modifiers.contains(.command) {
                setFocusedNode(nil)
                return true
            }

        case 17: // T - Create task
            if !modifiers.contains(.command) {
                createNodeType = "task"
                createNodeTitle = ""
                createNodeParentId = nil
                showingCreateDialog = true
                return true
            }

        case 45: // N - Create note
            createNodeType = "note"
            createNodeTitle = ""
            createNodeParentId = nil
            showingCreateDialog = true
            return true

        case 47: // Period/Dot - Toggle task
            performAction(.toggleTask)
            return true

        case 4: // H - Help
            performAction(.showHelp)
            return true

        case 12: // Q - Quick add to default folder
            Task {
                await createQuickTaskInDefaultFolder()
            }
            return true

        case 36: // Enter - Edit or activate
            performAction(.activateNode)
            return true

        case 49: // Space - Edit node
            isEditing = true
            return true

        case 126: // Arrow Up
            navigateToNode(direction: .up)
            return true

        case 125: // Arrow Down
            navigateToNode(direction: .down)
            return true

        case 123: // Arrow Left
            navigateToNode(direction: .left)
            return true

        case 124: // Arrow Right
            navigateToNode(direction: .right)
            return true

        default:
            break
        }

        return false
    }

    /// Node action types
    enum NodeAction {
        case copyNodeNames
        case deleteNode
        case showDetails
        case focusNode
        case showTags
        case executeSmartFolder
        case useTemplate
        case createQuickTask
        case toggleTask
        case showHelp
        case activateNode
        case expandNode
        case collapseNode
    }

    /// Perform a node action
    func performAction(_ action: NodeAction, nodeId: String? = nil) {
        let targetNodeId = nodeId ?? selectedNodeId
        guard let targetId = targetNodeId else {
            logger.log("⚠️ No node selected for action: \(action)", category: "TreeViewModel")
            return
        }

        guard let node = allNodes.first(where: { $0.id == targetId }) else {
            logger.log("⚠️ Node not found: \(targetId)", category: "TreeViewModel")
            return
        }

        logger.log("🎯 Performing action \(action) on node: \(node.title)", category: "TreeViewModel")

        switch action {
        case .copyNodeNames:
            copyNodeNamesToClipboard()

        case .deleteNode:
            deleteNode(node)

        case .showDetails:
            showingDetailsForNode = node

        case .focusNode:
            if node.nodeType == "smart_folder" {
                setFocusedNode(node.id)
                Task { await executeSmartFolder(node) }
            } else if node.nodeType != "note" {
                setFocusedNode(node.id)
            }

        case .showTags:
            if node.nodeType != "smart_folder" {
                showingTagPickerForNode = node
            }

        case .executeSmartFolder:
            if node.nodeType == "smart_folder" {
                Task { await executeSmartFolder(node) }
            }

        case .useTemplate:
            if node.nodeType == "template" {
                Task { await instantiateTemplate(node) }
            }

        case .createQuickTask:
            // This doesn't need a selected node
            Task { await createQuickTaskInDefaultFolder() }

        case .toggleTask:
            if node.nodeType == "task" {
                toggleTaskStatus(node)
            }

        case .showHelp:
            showingHelpWindow = true

        case .activateNode:
            if node.nodeType == "note" {
                showingNoteEditorForNode = node
            } else if !getChildren(of: node.id).isEmpty || node.nodeType == "smart_folder" {
                toggleExpansion(for: node.id)
            }

        case .expandNode:
            expandedNodes.insert(node.id)

        case .collapseNode:
            expandedNodes.remove(node.id)
        }
    }

    /// Navigation directions
    enum NavigationDirection {
        case up, down, left, right
    }

    /// Navigate to adjacent node
    func navigateToNode(direction: NavigationDirection) {
        guard let currentId = selectedNodeId else {
            // Select first root node if nothing selected
            if direction == .down, let firstNode = getRootNodes().first {
                setSelectedNode(firstNode.id)
            }
            return
        }

        logger.log("🔄 Navigating \(direction) from node: \(currentId)", category: "TreeViewModel")

        switch direction {
        case .up:
            navigateUp(from: currentId)
        case .down:
            navigateDown(from: currentId)
        case .left:
            navigateLeft(from: currentId)
        case .right:
            navigateRight(from: currentId)
        }
    }

    private func navigateUp(from nodeId: String) {
        // Get visible nodes in tree order
        let visibleNodes = getVisibleNodes()
        guard let currentIndex = visibleNodes.firstIndex(where: { $0.id == nodeId }),
              currentIndex > 0 else { return }

        setSelectedNode(visibleNodes[currentIndex - 1].id)
    }

    private func navigateDown(from nodeId: String) {
        let visibleNodes = getVisibleNodes()
        guard let currentIndex = visibleNodes.firstIndex(where: { $0.id == nodeId }),
              currentIndex < visibleNodes.count - 1 else { return }

        setSelectedNode(visibleNodes[currentIndex + 1].id)
    }

    private func navigateLeft(from nodeId: String) {
        guard let node = allNodes.first(where: { $0.id == nodeId }) else { return }

        if expandedNodes.contains(nodeId) && !getChildren(of: nodeId).isEmpty {
            // Collapse if expanded and has children
            collapseNode(nodeId)
        } else if let parentId = node.parentId {
            // Navigate to parent
            setSelectedNode(parentId)
        }
    }

    private func navigateRight(from nodeId: String) {
        guard let node = allNodes.first(where: { $0.id == nodeId }) else { return }
        let children = getChildren(of: nodeId)

        if !children.isEmpty {
            if !expandedNodes.contains(nodeId) {
                // Expand if collapsed and has children
                expandNode(nodeId)
            } else if let firstChild = children.first {
                // Navigate to first child if already expanded
                setSelectedNode(firstChild.id)
            }
        }
    }

    /// Get all visible nodes in tree order
    private func getVisibleNodes() -> [Node] {
        var visibleNodes: [Node] = []

        func addVisibleNodes(nodes: [Node], level: Int = 0) {
            for node in nodes {
                visibleNodes.append(node)
                if expandedNodes.contains(node.id) {
                    let children = getChildren(of: node.id)
                    addVisibleNodes(nodes: children, level: level + 1)
                }
            }
        }

        let rootNodes = focusedNodeId != nil
            ? getChildren(of: focusedNodeId!)
            : getRootNodes()
        addVisibleNodes(nodes: rootNodes)

        return visibleNodes
    }

    // MARK: - State Management Methods

    /// Set the selected node
    func setSelectedNode(_ nodeId: String?) {
        selectedNodeId = nodeId
        logger.log("✅ Selected node set to: \(nodeId ?? "nil")", category: "TreeViewModel")
    }

    /// Set the focused node
    func setFocusedNode(_ nodeId: String?) {
        focusedNodeId = nodeId
        if let nodeId = nodeId {
            expandedNodes.insert(nodeId) // Always expand when focusing
        }
        logger.log("🎯 Focused node set to: \(nodeId ?? "nil")", category: "TreeViewModel")
        NotificationCenter.default.post(name: .focusChanged, object: nil)
    }

    /// Expand a node
    func expandNode(_ nodeId: String) {
        expandedNodes.insert(nodeId)
        logger.log("📂 Expanded node: \(nodeId)", category: "TreeViewModel")
    }

    /// Collapse a node
    func collapseNode(_ nodeId: String) {
        expandedNodes.remove(nodeId)
        logger.log("📁 Collapsed node: \(nodeId)", category: "TreeViewModel")
    }

    /// Toggle expansion state
    func toggleExpansion(for nodeId: String) {
        if expandedNodes.contains(nodeId) {
            collapseNode(nodeId)
        } else {
            expandNode(nodeId)
        }
    }

    /// Copy node hierarchy to clipboard
    private func copyNodeNamesToClipboard() {
        logger.log("📋 Copying node names to clipboard", category: "TreeViewModel")

        var textToCopy = ""
        func addNodeToText(_ node: Node, level: Int) {
            let indent = String(repeating: "  ", count: level)
            textToCopy += "\(indent)\(node.title)\n"

            let children = getChildren(of: node.id)
            for child in children {
                addNodeToText(child, level: level + 1)
            }
        }

        // Copy focused node or selected node hierarchy
        if let focusedId = focusedNodeId,
           let focusedNode = allNodes.first(where: { $0.id == focusedId }) {
            addNodeToText(focusedNode, level: 0)
        } else if let selectedId = selectedNodeId,
                  let selectedNode = allNodes.first(where: { $0.id == selectedId }) {
            addNodeToText(selectedNode, level: 0)
        }

        if !textToCopy.isEmpty {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            logger.log("✅ Copied node hierarchy to clipboard", category: "TreeViewModel")
            #endif
        }
    }

    // MARK: - Quick Task Creation

    /// Create a quick task in the default folder
    func createQuickTaskInDefaultFolder() async {
        logger.log("📞 Creating quick task in default folder", category: "TreeViewModel")

        guard let dataManager = dataManager else {
            logger.error("❌ No DataManager available", category: "TreeViewModel")
            return
        }

        // Get the default folder ID
        guard let defaultNodeId = await dataManager.getDefaultFolder() else {
            logger.log("⚠️ No default folder set", level: .warning, category: "TreeViewModel")
            // Could show an alert here
            return
        }

        // Create a quick task in the default folder
        let taskTitle = "New Task \(Date().formatted(date: .abbreviated, time: .omitted))"
        if let newNode = await dataManager.createNode(
            title: taskTitle,
            type: "task",
            parentId: defaultNodeId
        ) {
            logger.log("✅ Created quick task: \(newNode.title) in default folder", category: "TreeViewModel")

            // Expand the default folder to show the new task
            expandedNodes.insert(defaultNodeId)

            // Select the new task
            selectedNodeId = newNode.id
        }
    }

    // MARK: - Smart Folder Execution

    func executeSmartFolder(_ node: Node) async {
        logger.log("📞 Executing smart folder: \(node.title)", category: "TreeViewModel")

        guard let dataManager = dataManager else {
            logger.log("⚠️ No DataManager available", level: .warning, category: "TreeViewModel")
            return
        }

        let resultNodes = await dataManager.executeSmartFolder(nodeId: node.id)

        await MainActor.run {
            if !resultNodes.isEmpty {
                logger.log("📝 Updating children for smart folder with \(resultNodes.count) nodes", category: "TreeViewModel")
                self.nodeChildren[node.id] = resultNodes
                // Expand the smart folder to show results
                self.expandedNodes.insert(node.id)
                logger.log("✅ UI updated with smart folder results", category: "TreeViewModel")
            } else {
                logger.log("⚠️ Smart folder returned no results", category: "TreeViewModel")
                // Clear any previous results
                self.nodeChildren[node.id] = []
                // Keep it expanded to show "no results" state
                self.expandedNodes.insert(node.id)
            }
        }
    }

    // MARK: - Template Instantiation

    func instantiateTemplate(_ template: Node) async {
        logger.log("📞 Instantiating template: \(template.title)", category: "TreeViewModel")

        guard let dataManager = dataManager else {
            logger.log("⚠️ No DataManager available", level: .warning, category: "TreeViewModel")
            return
        }

        // Use the template's target node if it has one
        let targetNodeId = template.templateData?.targetNodeId

        // Use DataManager to instantiate the template
        if let newNode = await dataManager.instantiateTemplate(
            templateId: template.id,
            parentId: targetNodeId  // Pass the target node to DataManager
        ) {
            logger.log("✅ Template instantiated successfully: \(newNode.title)", category: "TreeViewModel")

            // After refresh (done by DataManager), expand target node and focus the new node
            await MainActor.run {
                // Expand the target node if it exists
                if let targetId = targetNodeId {
                    self.expandedNodes.insert(targetId)
                }

                // Select and focus the newly created node
                self.selectedNodeId = newNode.id
                self.focusedNodeId = newNode.id
            }
        } else {
            logger.log("❌ Failed to instantiate template", level: .error, category: "TreeViewModel")
        }
    }

}