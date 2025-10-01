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
    // Node lookup cache for O(1) access
    private var nodeCache: [String: Node] = [:]
    @Published var nodeChildren: [String: [Node]] = [:]
    @Published var isLoading = false
    @Published var expandedNodes = Set<String>()
    @Published var selectedNodeId: String?
    @Published var focusedNodeId: String? = nil {
        didSet {
            resolveFocusedNode()
        }
    }
    @Published private(set) var focusedNode: Node? = nil
    var selectedNode: Node? {
        guard let selectedNodeId = selectedNodeId else { return nil }
        return allNodes.first { $0.id == selectedNodeId }
    }
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

    /// Set the DataManager instance and subscribe to its node updates
    func setDataManager(_ manager: DataManager) {
        self.dataManager = manager
        
        // Subscribe to DataManager's nodes changes
        manager.$nodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nodes in
                guard let self = self else { return }
                self.updateNodesFromDataManager(nodes)
            }
            .store(in: &cancellables)
        
    }

    /// Get all root nodes (nodes without a parent) sorted by sort order
    func getRootNodes() -> [Node] {
        let roots = allNodes.filter { $0.parentId == nil || $0.parentId == "" }
            .sorted { $0.sortOrder < $1.sortOrder }
        return roots
    }

    /// Get children of a specific node from the nodeChildren cache
    func getChildren(of nodeId: String) -> [Node] {
        let children = nodeChildren[nodeId] ?? []
        return children
    }

    /// Get the parent chain from root to the given node (excluding the node itself)
    func getParentChain(for node: Node) -> [Node] {
        var chain: [Node] = []
        var currentNode: Node? = node
        
        while let current = currentNode, let parentId = current.parentId, !parentId.isEmpty {
            if let parent = nodeCache[parentId] {
                chain.insert(parent, at: 0)
                currentNode = parent
            } else {
                break
            }
        }
        
        return chain
    }

    /// Update local state from DataManager's nodes - maintains caches and derived state
    internal func updateNodesFromDataManager(_ nodes: [Node]) {
        // No need to set allNodes anymore, it's computed from dataManager

        // Rebuild node cache for O(1) lookups
        nodeCache.removeAll()
        for node in nodes {
            nodeCache[node.id] = node
        }

        // Preserve smart folder results before rebuilding
        var smartFolderResults: [String: [Node]] = [:]
        for (nodeId, children) in nodeChildren {
            // Check if this is a smart folder with results
            // Use the cache we just built for O(1) lookup
            if let node = nodeCache[nodeId],
               node.nodeType == "smart_folder",
               !children.isEmpty {
                smartFolderResults[nodeId] = children
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

        // Resolve focused node after cache update
        resolveFocusedNode()

        // Validate consistency in debug builds
        #if DEBUG
        validateNodeConsistency()
        #endif
    }

    // MARK: - Data Consistency Helpers

    /// Validate that allNodes and nodeChildren are consistent
    private func validateNodeConsistency() {
        var issues: [String] = []

        // Check 1: All children in nodeChildren exist in allNodes
        for (parentId, children) in nodeChildren {
            for child in children {
                if nodeCache[child.id] == nil {
                    issues.append("Child \(child.id) in nodeChildren[\(parentId)] not found in allNodes")
                }
            }
        }

        // Check 2: All nodes with parentId have that parent in allNodes
        for node in allNodes {
            if let parentId = node.parentId {
                if nodeCache[parentId] == nil {
                    issues.append("Node \(node.id) references parent \(parentId) that doesn't exist in allNodes")
                }
            }
        }

        // Check 3: All parent-child relationships are reflected in nodeChildren
        for node in allNodes {
            if let parentId = node.parentId {
                if let siblings = nodeChildren[parentId] {
                    if !siblings.contains(where: { $0.id == node.id }) {
                        issues.append("Node \(node.id) with parent \(parentId) not found in nodeChildren[\(parentId)]")
                    }
                } else {
                    // Parent should have an entry in nodeChildren if it has children
                    issues.append("Parent \(parentId) of node \(node.id) has no entry in nodeChildren")
                }
            }
        }

        // Only log if issues found
        if !issues.isEmpty {
            logger.error("❌ Node consistency issues found:", category: "TreeViewModel")
            for issue in issues {
                logger.error("  - \(issue)", category: "TreeViewModel")
            }
        }
    }

    /// Initial load of nodes - only runs once per view lifecycle
    func initialLoad() async {
        guard !didLoad else {
            return
        }

        // logger.log("🔄 TreeViewModel initial load started", category: "TreeViewModel")
        isLoading = true
        didLoad = true

        await performLoad()
    }

    /// Force a full refresh of all nodes from the server
    func refreshNodes() async {
        // logger.log("🔄 TreeViewModel.refreshNodes() called - forcing full refresh", category: "TreeViewModel")
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
        // logger.log("🔄 Refreshing single node: \(nodeId)", category: "TreeViewModel")

        guard let dataManager = dataManager else {
            logger.error("❌ No DataManager available for single node refresh", category: "TreeViewModel")
            return
        }

        // Use DataManager to refresh the single node
        await dataManager.refreshNode(nodeId)
        // DataManager now handles error recovery internally by restoring previous state
    }

    private func performLoad() async {
        do {
            // Use DataManager if available, otherwise fall back to API directly
            let nodes: [Node]
            guard let dataManager = dataManager else {
                logger.error("❌ No DataManager available - cannot load nodes", category: "TreeViewModel")
                return // Early return, no error throw needed as this is caught in the do-catch
            }

            // Use syncAllData to load from cache when offline
            await dataManager.syncAllData()
            nodes = dataManager.nodes

            await MainActor.run {
                self.updateNodesFromDataManager(nodes)
                self.isLoading = false
            }
        } catch {
            logger.error("❌ Error loading nodes: \(error)", category: "TreeViewModel")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    /// Update a single node from the server
    func updateSingleNode(nodeId: String) async {
        // Delegate to refreshNode for consistency
        await refreshNode(nodeId: nodeId)
    }

    /// Prepare to delete a node (shows confirmation dialog)
    func deleteNode(_ node: Node) {
        nodeToDelete = node
        showingDeleteAlert = true
    }

    /// Confirm and execute node deletion with all descendants
    func confirmDeleteNode() async {
        guard let node = nodeToDelete, let dataManager = dataManager else {
            logger.log("❌ No node to delete or no dataManager", category: "TreeViewModel")
            return
        }

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
                }
                // If no previous, try next sibling
                else if currentIndex < siblings.count - 1 {
                    nextSelectionId = siblings[currentIndex + 1].id
                }
                // No siblings, selection will be nil
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

        // Refresh parent node to ensure its children list is consistent
        if let parentId = node.parentId {
            await dataManager.refreshNode(parentId)
            // DataManager handles error recovery by preserving consistency
        }

        // Handle UI-specific state cleanup and selection
        await MainActor.run {
            self.batchUI {
                // If we were focused on a deleted node, unfocus
                if let focusedId = self.focusedNodeId, nodesToRemove.contains(focusedId) {
                    self.focusedNodeId = nil
                }

                // Set the new selection
                self.selectedNodeId = nextSelectionId

                // Clear the nodeToDelete
                self.nodeToDelete = nil
            }

            #if DEBUG
            // Validate data consistency after deletion
            self.validateNodeConsistency()
            #endif

        }
    }

    /// Toggle the completion status of a task node
    func toggleTaskStatus(_ node: Node) {
        
        guard let dataManager = dataManager else {
            logger.error("❌ No dataManager available", category: "TreeViewModel")
            return
        }
        
        
        Task {
            // Update backend - the DataManager subscription will handle the UI update
            if let updatedNode = await dataManager.toggleNodeCompletion(node) {
                // The subscription to DataManager.nodes will automatically update our view
                // But we also need to update smart folder results if this node is in them
                await MainActor.run {
                    // Update the node in any smart folder results
                    for (parentId, children) in nodeChildren {
                        if let index = children.firstIndex(where: { $0.id == updatedNode.id }) {
                            var updatedChildren = children
                            updatedChildren[index] = updatedNode
                            nodeChildren[parentId] = updatedChildren
                            logger.log("✅ Updated node in smart folder results", category: "TreeViewModel")
                        }
                    }
                }
            } else {
                logger.error("❌ toggleNodeCompletion returned nil", category: "TreeViewModel")
            }
        }
    }

    /// Update the title of a node
    func updateNodeTitle(nodeId: String, newTitle: String) async {
        guard let dataManager = dataManager else {
            logger.log("❌ No dataManager available", category: "TreeViewModel")
            return
        }

        guard let node = nodeCache[nodeId] else {
            logger.log("❌ Node not found: \(nodeId)", category: "TreeViewModel")
            return
        }


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
            // The subscription to DataManager.nodes will handle all UI updates
        } else {
            logger.log("⚠️ Node update returned nil - might be offline and queued", category: "TreeViewModel")
            // In offline mode, the update is queued and DataManager handles local updates
        }
    }

    // MARK: - Drag and Drop

    /// Reorder nodes via drag and drop, updating sort orders for all affected siblings
    func performReorder(draggedNode: Node, targetNode: Node, position: DropPosition, message: String) async {

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
            }
        }

        // Send updates to backend
        guard let dataManager = dataManager else {
            logger.log("❌ No dataManager available", category: "TreeViewModel")
            return
        }

        // Update each node's sort order
        for update in updates {
            if let node = nodeCache[update.nodeId] {

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

        // Refresh the parent to ensure consistent ordering
        if let parentId = draggedNode.parentId {
            await dataManager.refreshNode(parentId)
            // DataManager handles error recovery by preserving consistency
        } else {
            // For root nodes, refresh all root nodes
            await dataManager.syncAllData()
        }

        await MainActor.run {
            #if DEBUG
            // Validate data consistency after reordering
            self.validateNodeConsistency()
            #endif
        }

    }

    /// Show an alert message for drag and drop operations
    func showDropAlert(message: String) {
        dropAlertMessage = message
        showingDropAlert = true
    }

    /// Create a new node with specified type, title, and optional parent
    func createNode(type: String, title: String, parentId: String?) async {
        guard let dataManager = dataManager else {
            logger.log("❌ No dataManager available", category: "TreeViewModel")
            return
        }


        if let createdNode = await dataManager.createNode(
            title: title,
            type: type,
            content: nil,
            parentId: parentId,
            tags: []
        ) {

            // The DataManager subscription will update allNodes and nodeChildren automatically
            // We only need to expand the parent if needed
            // Ensure parent's children are consistent
            if let parentId = createdNode.parentId {
                await dataManager.refreshNode(parentId)
                // DataManager handles error recovery by preserving consistency
            }

            await MainActor.run {
                if let parentId = createdNode.parentId {
                    // Expand parent to show the new node
                    self.expandedNodes.insert(parentId)
                }

                #if DEBUG
                // Validate data consistency
                self.validateNodeConsistency()
                #endif
            }
        } else {
            logger.log("❌ Failed to create node", category: "TreeViewModel")
        }
    }

    // MARK: - UI Intent Methods

    /// Centralized keyboard event handling
    #if os(macOS)
    func handleKeyPress(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        logger.log("🎯 TreeViewModel.handleKeyPress CALLED", category: "KEYBOARD-VM")
        logger.log("  - keyCode: \(keyCode)", category: "KEYBOARD-VM")
        logger.log("  - modifiers: \(modifiers.rawValue)", category: "KEYBOARD-VM")
        logger.log("  - selectedNodeId: \(selectedNodeId ?? "nil")", category: "KEYBOARD-VM")
        logger.log("  - focusedNodeId: \(focusedNodeId ?? "nil")", category: "KEYBOARD-VM")
        logger.log("  - isEditing: \(isEditing)", category: "KEYBOARD-VM")
        logger.log("  - showingCreateDialog: \(showingCreateDialog)", category: "KEYBOARD-VM")

        // Handle Command key combinations
        if modifiers.contains(.command) {
            logger.log("📌 Processing COMMAND key combo in TreeViewModel", category: "KEYBOARD-VM")
            switch keyCode {
            case 8: // C - Copy node names
                logger.log("  🔍 Case 8: Cmd+C - Copy", category: "KEYBOARD-VM")
                if showingNoteEditorForNode != nil {
                    logger.log("    ❌ Note editor is showing - not handling", category: "KEYBOARD-VM")
                    return false  // Let note editor handle it
                }
                // logger.log("    ✅ Performing copyNodeNames action", category: "KEYBOARD-VM")
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

            case 5: // G - ATTEMPT 8: Test alternative key for tags
                logger.log("🧪 ATTEMPT 8: Cmd+G test - calling performAction(.showTags)", category: "KEYBOARD-TEST")
                performAction(.showTags)
                logger.log("✅ ATTEMPT 8: Cmd+G test - performAction(.showTags) completed", category: "KEYBOARD-TEST")
                return true

            case 17: // T - Tags
                logger.log("🎯 ATTEMPT 8: Cmd+T detected - calling performAction(.showTags)", category: "KEYBOARD-VM")
                performAction(.showTags)
                logger.log("✅ ATTEMPT 8: performAction(.showTags) completed", category: "KEYBOARD-VM")
                return true

            case 14: // E - Execute smart folder
                performAction(.executeSmartFolder)
                return true

            case 32: // U - Use template
                performAction(.useTemplate)
                return true

            case 12: // Q - Quick task
                Task { performAction(.createQuickTask) }
                return true

            case 51: // Delete key with Cmd - Delete node
                logger.log("  🔍 Case 51: Cmd+Delete - Delete node", category: "KEYBOARD-VM")
                // logger.log("    ✅ Performing deleteNode action", category: "KEYBOARD-VM")
                performAction(.deleteNode)
                return true

            case 46: // M - Show details/metadata
                performAction(.showDetails)
                return true

            case 44: // Slash - Help (Cmd+/)
                logger.log("  🔍 Case 44: Cmd+/ - Help", category: "KEYBOARD-VM")
                // logger.log("    ✅ Performing showHelp action", category: "KEYBOARD-VM")
                performAction(.showHelp)
                return true

            case 36: // Return with Cmd - Open note editor
                if let node = nodeCache[selectedNodeId ?? ""],
                   node.nodeType == "note" {
                    openNoteEditor(node)
                    return true
                }
                return false

            default:
                logger.log("  ⚠️ Unhandled Cmd+keyCode: \(keyCode)", category: "KEYBOARD-VM")
                break
            }
        } else {
            logger.log("📌 Processing NON-COMMAND key in TreeViewModel", category: "KEYBOARD-VM")
        }

        // Handle non-command shortcuts
        logger.log("📌 Checking non-command shortcuts", category: "KEYBOARD-VM")
        switch keyCode {
        case 3: // F - unfocus (when no command modifier)
            if !modifiers.contains(.command) {
                setFocusedNode(nil)
                return true
            }

        case 17: // T - Create task
            logger.log("  🔍 Case 17: T key", category: "KEYBOARD-VM")
            if !modifiers.contains(.command) {
                // logger.log("    ✅ Creating task - setting showingCreateDialog = true", category: "KEYBOARD-VM")
                createNodeType = "task"
                createNodeTitle = ""
                createNodeParentId = nil
                showingCreateDialog = true
                return true
            }
            logger.log("    ❌ Has Command modifier - not handling", category: "KEYBOARD-VM")

        case 45: // N - Create note
            logger.log("  🔍 Case 45: N key - Create note", category: "KEYBOARD-VM")
            // logger.log("    ✅ Creating note - setting showingCreateDialog = true", category: "KEYBOARD-VM")
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
            logger.log("  🔍 Case 126: Arrow Up", category: "KEYBOARD-VM")
            // logger.log("    ✅ Navigating up", category: "KEYBOARD-VM")
            navigateToNode(direction: .up)
            return true

        case 125: // Arrow Down
            logger.log("  🔍 Case 125: Arrow Down", category: "KEYBOARD-VM")
            // logger.log("    ✅ Navigating down", category: "KEYBOARD-VM")
            navigateToNode(direction: .down)
            return true

        case 123: // Arrow Left
            logger.log("  🔍 Case 123: Arrow Left", category: "KEYBOARD-VM")
            // logger.log("    ✅ Navigating left", category: "KEYBOARD-VM")
            navigateToNode(direction: .left)
            return true

        case 124: // Arrow Right
            logger.log("  🔍 Case 124: Arrow Right", category: "KEYBOARD-VM")
            // logger.log("    ✅ Navigating right", category: "KEYBOARD-VM")
            navigateToNode(direction: .right)
            return true

        case 53: // Escape key
            logger.log("  🔍 Case 53: Escape key", category: "KEYBOARD-VM")
            // Handle escape in priority order
            if showingDeleteAlert {
                // logger.log("    ✅ Closing delete alert", category: "KEYBOARD-VM")
                // Close delete alert
                showingDeleteAlert = false
                nodeToDelete = nil
                return true
            } else if isEditing {
                // logger.log("    ✅ Stopping edit mode", category: "KEYBOARD-VM")
                // Stop editing
                isEditing = false
                return true
            } else if focusedNodeId != nil {
                // logger.log("    ✅ Unfocusing node", category: "KEYBOARD-VM")
                // Unfocus node
                setFocusedNode(nil)
                return true
            }
            logger.log("    ❌ Nothing to escape from", category: "KEYBOARD-VM")
            return false

        default:
            logger.log("  ⚠️ Unhandled keyCode: \(keyCode)", category: "KEYBOARD-VM")
            break
        }

        logger.log("❌❌❌ TreeViewModel NOT HANDLING key - will cause BEEP", category: "KEYBOARD-VM")
        return false
    }
    #endif

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
        let targetNodeId = nodeId ?? selectedNodeId ?? focusedNodeId
        guard let targetId = targetNodeId else {
            logger.log("⚠️ No node selected or focused for action: \(action)", category: "TreeViewModel")
            return
        }

        guard let node = nodeCache[targetId] else {
            logger.log("⚠️ Node not found: \(targetId)", category: "TreeViewModel")
            return
        }

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
            logger.log("🎯 ATTEMPT 8: performAction(.showTags) called", category: "KEYBOARD-VM")
            logger.log("  - node.id: \(node.id)", category: "KEYBOARD-VM")
            logger.log("  - node.nodeType: \(node.nodeType)", category: "KEYBOARD-VM")
            if node.nodeType != "smart_folder" {
                logger.log("  ✅ Setting showingTagPickerForNode = \(node.title)", category: "KEYBOARD-VM")
                logger.log("  🔍 ATTEMPT 10: Before setting - showingTagPickerForNode = \(showingTagPickerForNode?.title ?? "nil")", category: "UI-STATE")
                showingTagPickerForNode = node
                logger.log("  🔍 ATTEMPT 10: After setting - showingTagPickerForNode = \(showingTagPickerForNode?.title ?? "nil")", category: "UI-STATE")
                logger.log("  🔍 ATTEMPT 10: Node being set - id: \(node.id), title: \(node.title), type: \(node.nodeType)", category: "UI-STATE")
            } else {
                logger.log("  ❌ Not showing tag picker for smart_folder", category: "KEYBOARD-VM")
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
                openNoteEditor(node)
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
        logger.log("  NAV-UP: From nodeId: \(nodeId)", category: "NAVIGATION")
        logger.log("  NAV-UP: Visible nodes count: \(visibleNodes.count)", category: "NAVIGATION")
        logger.log("  NAV-UP: Visible node IDs: \(visibleNodes.map { $0.id })", category: "NAVIGATION")

        guard let currentIndex = visibleNodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.log("  NAV-UP: ❌ Current node not in visible nodes!", category: "NAVIGATION")
            return
        }
        guard currentIndex > 0 else {
            logger.log("  NAV-UP: ❌ Already at top", category: "NAVIGATION")
            return
        }

        let newNodeId = visibleNodes[currentIndex - 1].id
        // logger.log("  NAV-UP: ✅ Moving to: \(newNodeId)", category: "NAVIGATION")
        setSelectedNode(newNodeId)
    }

    private func navigateDown(from nodeId: String) {
        let visibleNodes = getVisibleNodes()
        logger.log("  NAV-DOWN: From nodeId: \(nodeId)", category: "NAVIGATION")
        logger.log("  NAV-DOWN: Visible nodes count: \(visibleNodes.count)", category: "NAVIGATION")
        logger.log("  NAV-DOWN: Visible node IDs: \(visibleNodes.map { $0.id })", category: "NAVIGATION")

        guard let currentIndex = visibleNodes.firstIndex(where: { $0.id == nodeId }) else {
            logger.log("  NAV-DOWN: ❌ Current node not in visible nodes!", category: "NAVIGATION")
            return
        }
        guard currentIndex < visibleNodes.count - 1 else {
            logger.log("  NAV-DOWN: ❌ Already at bottom", category: "NAVIGATION")
            return
        }

        let newNodeId = visibleNodes[currentIndex + 1].id
        // logger.log("  NAV-DOWN: ✅ Moving to: \(newNodeId)", category: "NAVIGATION")
        setSelectedNode(newNodeId)
    }

    private func navigateLeft(from nodeId: String) {
        guard let node = nodeCache[nodeId] else { return }

        // If we're in focus mode and this is the focused node, exit focus first
        if focusedNodeId == nodeId {
            // Exit focus mode - go back to parent or root view
            batchUI {
                if let parentId = node.parentId {
                    focusedNodeId = parentId
                    selectedNodeId = nodeId // Keep selection on current node
                } else {
                    focusedNodeId = nil // Exit to root view
                    selectedNodeId = nodeId // Keep selection on current node
                }
            }
        } else if expandedNodes.contains(nodeId) && !getChildren(of: nodeId).isEmpty {
            // Collapse if expanded and has children
            collapseNode(nodeId)
        } else if let parentId = node.parentId {
            // Navigate to parent
            setSelectedNode(parentId)
        }
    }

    private func navigateRight(from nodeId: String) {
        guard let node = nodeCache[nodeId] else { return }

        // Special handling for different node types
        switch node.nodeType {
        case "note":
            // Right arrow on note opens the note editor
            openNoteEditor(node)
            return

        case "smart_folder":
            // Smart folders: execute and expand, but don't focus
            if !expandedNodes.contains(nodeId) {
                // Execute and expand to show results
                Task {
                    await executeSmartFolder(node)
                }
                expandNode(nodeId)
            }
            // Already expanded - do nothing on subsequent right arrows
            return

        default:
            // Normal folder/task behavior
            let children = getChildren(of: nodeId)

            if !children.isEmpty {
                if !expandedNodes.contains(nodeId) {
                    // First click: Expand if collapsed and has children
                    expandNode(nodeId)
                } else {
                    // Second click: Focus on the node (enter focus mode)
                    setFocusedNode(nodeId)
                }
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

        let rootNodes: [Node]
        if let focusedId = focusedNodeId {
            logger.log("  getVisibleNodes: In FOCUS mode - focusedId: \(focusedId)", category: "NAVIGATION")
            // When focused, we should show the focused node AND its children
            // Not just the children!
            if let focusedNode = nodeCache[focusedId] {
                rootNodes = [focusedNode]
            } else {
                rootNodes = getChildren(of: focusedId)
            }
        } else {
            logger.log("  getVisibleNodes: In ROOT mode", category: "NAVIGATION")
            rootNodes = getRootNodes()
        }
        addVisibleNodes(nodes: rootNodes)

        return visibleNodes
    }

    // MARK: - State Management Methods

    /// Batch multiple UI updates to reduce rendering churn
    private func batchUI(_ updates: () -> Void) {
        withTransaction(Transaction(animation: nil)) {
            updates()
        }
    }

    /// Set the selected node
    func setSelectedNode(_ nodeId: String?) {
        selectedNodeId = nodeId
    }

    /// Low-level setter for focused node ID - does NOT select the node
    /// For user-initiated focus actions, use focusOnNode(_:) instead which handles selection
    /// This is primarily for programmatic focus changes (e.g., tab restoration, keyboard navigation)
    func setFocusedNode(_ nodeId: String?) {
        focusedNodeId = nodeId
        if let nodeId = nodeId {
            expandedNodes.insert(nodeId) // Always expand when focusing
        }
    }

    /// Resolve the focused node from the cache
    private func resolveFocusedNode() {
        focusedNode = focusedNodeId.flatMap { nodeCache[$0] }
    }

    /// Expand a node
    func expandNode(_ nodeId: String) {
        expandedNodes.insert(nodeId)
    }

    /// Collapse a node - batches UI updates
    func collapseNode(_ nodeId: String) {
        batchUI {
            var expanded = expandedNodes
            expanded.remove(nodeId)
            expandedNodes = expanded

            // If the currently selected node is a descendant of the collapsed node,
            // move selection to the collapsed parent node
            if let selectedId = selectedNodeId {
                if isDescendant(selectedId, of: nodeId) {
                    selectedNodeId = nodeId
                    // Also clear focus if focused node was a descendant
                    if let focusedId = focusedNodeId, isDescendant(focusedId, of: nodeId) {
                        focusedNodeId = nil
                    }
                }
            }
        }
    }

    /// Check if a node is a descendant of another node
    private func isDescendant(_ childId: String, of ancestorId: String) -> Bool {
        var currentId: String? = childId
        while let id = currentId {
            // Get parent of current node
            if let parent = nodeCache[id]?.parentId {
                if parent == ancestorId {
                    return true
                }
                currentId = parent
            } else {
                break
            }
        }
        return false
    }

    /// Open note editor for a node (unified method)
    func openNoteEditor(_ node: Node) {
        guard node.nodeType == "note" else { return }
        showingNoteEditorForNode = node
    }

    /// Show tag picker for a node (unified method)
    func showTagPicker(_ node: Node) {
        guard node.nodeType != "smart_folder" else { return } // Smart folders don't support tags
        showingTagPickerForNode = node
    }

    /// Show details for a node (unified method)
    func showDetails(_ node: Node) {
        showingDetailsForNode = node
    }

    /// Focus on a node with smart folder handling (unified method) - batches UI updates
    func focusOnNode(_ node: Node) {
        batchUI {
            focusedNodeId = node.id
            selectedNodeId = node.id  // Also select when focusing
            var expanded = expandedNodes
            expanded.insert(node.id)
            expandedNodes = expanded
        }

        // Execute smart folder if focusing on one
        if node.nodeType == "smart_folder" {
            Task {
                await executeSmartFolder(node)
            }
        }
    }

    /// Select and focus a node with expansion (composite intent)
    func selectAndFocus(_ nodeId: String) {
        batchUI {
            selectedNodeId = nodeId
            focusedNodeId = nodeId
            var expanded = expandedNodes
            expanded.insert(nodeId)
            expandedNodes = expanded
        }
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
           let focusedNode = nodeCache[focusedId] {
            addNodeToText(focusedNode, level: 0)
        } else if let selectedId = selectedNodeId,
                  let selectedNode = nodeCache[selectedId] {
            addNodeToText(selectedNode, level: 0)
        }

        if !textToCopy.isEmpty {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            #endif
        }
    }

    // MARK: - Quick Task Creation

    /// Create a quick task in the default folder
    func createQuickTaskInDefaultFolder() async {

        guard let dataManager = dataManager else {
            logger.error("❌ No DataManager available", category: "TreeViewModel")
            return
        }

        // Get the default folder ID
        guard let defaultNodeId = await dataManager.getDefaultFolder() else {
            logger.log("⚠️ No default folder set", category: "TreeViewModel", level: .warning)
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

            // Batch UI updates: expand and select
            batchUI {
                var expanded = expandedNodes
                expanded.insert(defaultNodeId)
                expandedNodes = expanded
                selectedNodeId = newNode.id
            }
        }
    }

    // MARK: - Smart Folder Execution

    /// Execute a smart folder's rules and display results
    func executeSmartFolder(_ node: Node) async {

        guard let dataManager = dataManager else {
            logger.log("⚠️ No DataManager available", category: "TreeViewModel", level: .warning)
            return
        }

        let resultNodes = await dataManager.executeSmartFolder(nodeId: node.id)

        await MainActor.run {
            if !resultNodes.isEmpty {
                self.nodeChildren[node.id] = resultNodes
                // Expand the smart folder to show results
                self.expandedNodes.insert(node.id)
            } else {
                // Clear any previous results
                self.nodeChildren[node.id] = []
                // Keep it expanded to show "no results" state
                self.expandedNodes.insert(node.id)
            }

            #if DEBUG
            // Validate data consistency after smart folder execution
            self.validateNodeConsistency()
            #endif
        }
    }

    // MARK: - Template Instantiation

    /// Create a new node hierarchy from a template
    func instantiateTemplate(_ template: Node) async {

        guard let dataManager = dataManager else {
            logger.log("⚠️ No DataManager available", category: "TreeViewModel", level: .warning)
            return
        }

        // Use the template's target node if it has one
        let targetNodeId = template.templateData?.targetNodeId

        // Use DataManager to instantiate the template
        if let newNode = await dataManager.instantiateTemplate(
            templateId: template.id,
            parentId: targetNodeId  // Pass the target node to DataManager
        ) {

            // Retry logic: Wait for node to appear in local data (eventual consistency)
            var retryCount = 0
            let maxRetries = 3
            let retryDelay: UInt64 = 500_000_000 // 0.5 seconds in nanoseconds

            while retryCount < maxRetries {
                if nodeCache[newNode.id] != nil {
                    break
                }

                retryCount += 1

                // Wait briefly for data to sync
                try? await Task.sleep(nanoseconds: retryDelay)

                // Refresh the parent node to get updated children
                if let targetId = targetNodeId {
                    await dataManager.refreshNode(targetId)
                    // DataManager handles error recovery by preserving consistency
                }
            }

            // IMPORTANT: Refresh the new node itself to load its children
            // This ensures the template's content is loaded when we focus on it
            await dataManager.refreshNode(newNode.id)

            // After refresh (done by DataManager), batch UI updates
            await MainActor.run {
                self.batchUI {
                    // Build expanded set with both target and new node
                    var expanded = self.expandedNodes
                    if let targetId = targetNodeId {
                        expanded.insert(targetId)
                    }
                    expanded.insert(newNode.id)

                    // Apply all state changes at once
                    self.expandedNodes = expanded
                    self.selectedNodeId = newNode.id
                    self.focusedNodeId = newNode.id
                }
            }
        } else {
            logger.log("❌ Failed to instantiate template", category: "TreeViewModel", level: .error)
        }
    }

}