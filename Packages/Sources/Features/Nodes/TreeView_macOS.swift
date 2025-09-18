#if os(macOS)
import SwiftUI
import AppKit
import Core
import Models
import Services
import Networking

private let logger = Logger.shared

public struct TreeView_macOS: View {
    @StateObject private var viewModel = TreeViewModel()
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    @FocusState private var isTreeFocused: Bool
    @State private var keyEventMonitor: Any?

    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumb navigation
                if viewModel.focusedNodeId != nil {
                    BreadcrumbBar(
                        focusedNode: viewModel.currentFocusedNode,
                        parentChain: viewModel.currentFocusedNode.map { viewModel.getParentChain(for: $0) } ?? [],
                        onNodeTap: { nodeId in
                            logger.log("🎯 TreeView: Setting focusedNodeId to \(nodeId)", category: "TreeView")
                            viewModel.focusedNodeId = nodeId
                        },
                        onExitFocus: {
                            logger.log("🎯 TreeView: Clearing focusedNodeId", category: "TreeView")
                            viewModel.focusedNodeId = nil
                        }
                    )
                }
                
                // Main content
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            if viewModel.isLoading {
                                LoadingView()
                                    .padding()
                            } else {
                                TreeContent(
                                    viewModel: viewModel,
                                    fontSize: CGFloat(treeFontSize),
                                    lineSpacing: CGFloat(treeLineSpacing)
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.selectedNodeId) { newNodeId in
                        // Only scroll if we have a selected node
                        guard let nodeId = newNodeId else { return }

                        // Small delay to ensure view hierarchy is updated
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                // Simple approach: always ensure the node is visible
                                // SwiftUI will only scroll if needed
                                scrollProxy.scrollTo(nodeId, anchor: nil)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                // Keep keyboard focus without a giant ring by focusing a tiny view
                .background(alignment: .topLeading) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .focusable()
                        .focused($isTreeFocused)
                        .accessibilityHidden(true)
                }
                .onTapGesture {
                    // Ensure focus when clicking on the tree view area
                    if !isTreeFocused {
                        logger.log("🎯 Setting focus via tap gesture", category: "TreeView")
                        isTreeFocused = true
                    }
                }
                .onChange(of: viewModel.isEditing) { isEditing in
                    if !isEditing {
                        // When editing ends, restore focus to tree
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            logger.log("🎯 Restoring focus to tree after editing", category: "TreeView")
                            self.isTreeFocused = true
                        }
                    }
                }
                .onMoveCommand { direction in
                    // Don't handle arrow keys when in edit mode
                    guard !viewModel.isEditing else { return }

                    switch direction {
                    case .up:
                        moveToPreviousSibling()
                    case .down:
                        moveToNextSibling()
                    case .left:
                        moveToParent()
                    case .right:
                        moveToFirstChild()
                    default:
                        break
                    }
                }
                .onAppear {
                    setupKeyEventMonitor()
                    // Set focus when view appears (e.g., after login)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        logger.log("🎯 Setting initial focus to tree view", category: "TreeView")
                        self.isTreeFocused = true
                        // Also make the window key and first responder
                        if let window = NSApp.keyWindow {
                            window.makeKey()
                            window.makeFirstResponder(window.contentView)
                        }
                    }
                }
                .onDisappear {
                    // Clean up keyboard monitor to prevent leaks
                    if let monitor = keyEventMonitor {
                        NSEvent.removeMonitor(monitor)
                        keyEventMonitor = nil
                    }
                }
            }
            .navigationTitle(viewModel.currentFocusedNode?.title ?? "All Nodes")
            .toolbar {
                TreeToolbar(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingCreateDialog) {
                CreateNodeSheet(viewModel: viewModel)
                    .environmentObject(dataManager)
            }
            .sheet(item: $viewModel.showingNoteEditorForNode) { node in
                NoteEditorView(node: node) {
                    await viewModel.loadAllNodes()
                }
            }
            .sheet(item: $viewModel.showingDetailsForNode) { node in
                NodeDetailsView(nodeId: node.id, treeViewModel: viewModel)
            }
            .sheet(item: $viewModel.showingTagPickerForNode) { node in
                TagPickerView(node: node) {
                    // Just reload the single node to get updated tags
                    await viewModel.updateSingleNode(nodeId: node.id)
                }
            }
            .sheet(isPresented: $viewModel.showingHelpWindow) {
                KeyboardShortcutsHelpView()
            }
            .onChange(of: viewModel.showingNoteEditorForNode != nil) { isShowing in
                if isShowing {
                    // Note editor is showing, remove keyboard monitor
                    if let monitor = keyEventMonitor {
                        NSEvent.removeMonitor(monitor)
                        keyEventMonitor = nil
                    }
                } else {
                    // Note editor closed, restore keyboard monitor
                    setupKeyEventMonitor()
                }
            }
            .alert("Delete Node", isPresented: $viewModel.showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    viewModel.nodeToDelete = nil
                }

                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.confirmDeleteNode()
                    }
                }
                .keyboardShortcut(.defaultAction)
            } message: {
                if let node = viewModel.nodeToDelete {
                    Text("Delete \"\(node.title)\" and all its children?\n\nPress Return to delete, Escape to cancel")
                } else {
                    Text("Delete this node and all its children?")
                }
            }
            .task {
                // Set dataManager first, before loading nodes
                logger.log("📞 Setting dataManager on viewModel (in task)", category: "TreeView")
                viewModel.setDataManager(dataManager)
                logger.log("✅ DataManager set, now loading nodes", category: "TreeView")
                await viewModel.loadAllNodes()

                // Select first root node after loading
                if let firstRoot = viewModel.getRootNodes().first {
                    viewModel.selectedNodeId = firstRoot.id
                }
            }
            .onAppear {
                // Also set in onAppear as a backup
                logger.log("📞 Setting dataManager on viewModel (in onAppear)", category: "TreeView")
                logger.log("DataManager exists: \(String(describing: dataManager))", category: "TreeView")
                viewModel.setDataManager(dataManager)
                logger.log("✅ DataManager set on viewModel", category: "TreeView")
            }
        }
    }

    private func setupKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only process keyboard events when tree is focused
            if !self.isTreeFocused {
                return event
            }

            // Special handling for Escape key when delete alert is showing
            if self.viewModel.showingDeleteAlert && event.keyCode == 53 { // Escape key
                logger.log("⌨️ Escape pressed - closing delete alert", category: "TreeView")
                self.viewModel.showingDeleteAlert = false
                self.viewModel.nodeToDelete = nil
                return nil // Consume the event
            }

            // Don't process keyboard events when any modal is showing
            if viewModel.showingDeleteAlert ||
               viewModel.showingCreateDialog ||
               viewModel.showingDetailsForNode != nil ||
               viewModel.showingTagPickerForNode != nil ||
               viewModel.showingHelpWindow {
                return event
            }

            // Check if first responder is a text field/view - if so, don't intercept
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                if firstResponder is NSTextView || firstResponder is NSTextField {
                    // Don't intercept any keys when editing - let TextField handle them
                    return event
                }
            }

            // Normal navigation mode - only handle space bar since arrows are handled by onMoveCommand
            return self.handleKeyEvent(event) ? nil : event
        }
        logger.log("✅ Key event monitor setup complete", category: "TreeView")
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Edit mode is already handled in setupKeyEventMonitor
        // Arrow keys are now handled by .onMoveCommand

        // Handle Command key combinations
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 2: // D key - Details
                if event.modifierFlags.contains(.shift) {
                    // Cmd+Shift+D - Delete
                    logger.log("⌨️ Cmd+Shift+D pressed - delete node", category: "TreeView")
                    if let selectedId = viewModel.selectedNodeId,
                       let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        viewModel.deleteNode(selectedNode)
                    }
                    return true
                } else {
                    // Cmd+D - Details
                    logger.log("⌨️ Cmd+D pressed - show details", category: "TreeView")
                    if let selectedId = viewModel.selectedNodeId,
                       let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        viewModel.showingDetailsForNode = selectedNode
                    }
                    return true
                }

            case 3: // F key - Focus
                logger.log("⌨️ Cmd+F pressed - focus on node", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                    if selectedNode.nodeType == "smart_folder" {
                        // Smart folders: focus AND execute their rule
                        logger.log("🧩 Smart folder detected, focusing and executing rule", category: "TreeView")
                        viewModel.focusedNodeId = selectedNode.id
                        viewModel.expandedNodes.insert(selectedNode.id)
                        Task {
                            await executeSmartFolderRule(for: selectedNode)
                        }
                    } else if selectedNode.nodeType != "note" {
                        // Regular focus for non-note, non-smart-folder nodes
                        viewModel.focusedNodeId = selectedNode.id
                        viewModel.expandedNodes.insert(selectedNode.id)
                    }
                }
                return true

            case 17: // T key - Tags
                logger.log("⌨️ Cmd+T pressed - show tags", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                   selectedNode.nodeType != "smart_folder" {  // Smart folders don't support tags
                    viewModel.showingTagPickerForNode = selectedNode
                }
                return true

            case 14: // E key - Execute (smart folders)
                logger.log("⌨️ Cmd+E pressed - execute smart folder", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                   selectedNode.nodeType == "smart_folder" {
                    Task {
                        await executeSmartFolderRule(for: selectedNode)
                    }
                }
                return true

            case 32: // U key - Use template
                logger.log("⌨️ Cmd+U pressed - use template", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                   selectedNode.nodeType == "template" {
                    Task {
                        await instantiateTemplate(selectedNode)
                    }
                }
                return true

            default:
                break
            }
        }

        // Handle other keys without modifiers
        switch event.keyCode {
        case 47: // Period/Dot key - Toggle task completion
            logger.log("⌨️ Dot pressed - toggle task", category: "TreeView")
            if let selectedId = viewModel.selectedNodeId,
               let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
               selectedNode.nodeType == "task" {
                logger.log("✅ Toggling task status for: \(selectedNode.title)", category: "TreeView")
                viewModel.toggleTaskStatus(selectedNode)
            }
            return true

        case 4: // H key - Help
            logger.log("⌨️ H pressed - showing help", category: "TreeView")
            viewModel.showingHelpWindow = true
            return true

        case 17 where !event.modifierFlags.contains(.command): // T key (without Cmd)
            logger.log("⌨️ T pressed - creating new task", category: "TreeView")
            viewModel.createNodeType = "task"
            viewModel.createNodeTitle = ""
            viewModel.showingCreateDialog = true
            return true

        case 45: // N key
            logger.log("⌨️ N pressed - creating new note", category: "TreeView")
            viewModel.createNodeType = "note"
            viewModel.createNodeTitle = ""
            viewModel.showingCreateDialog = true
            return true

        case 3 where !event.modifierFlags.contains(.command): // F key (without Cmd)
            logger.log("⌨️ F pressed - creating new folder", category: "TreeView")
            viewModel.createNodeType = "folder"
            viewModel.createNodeTitle = ""
            viewModel.showingCreateDialog = true
            return true

        case 49: // Space bar
            logger.log("⌨️ Space bar pressed", category: "TreeView")
            if let selectedId = viewModel.selectedNodeId {
                logger.log("✏️ Entering edit mode for node: \(selectedId)", category: "TreeView")
                viewModel.isEditing = true
            } else {
                logger.log("⚠️ No node selected, cannot enter edit mode", category: "TreeView")
            }
            return true
        case 36: // Enter/Return key (in case not in edit mode)
            logger.log("⚠️ Not in edit mode, ignoring Enter key", category: "TreeView")
            return true
        default:
            return false
        }
    }

    private func moveToNextSibling() {
        logger.log("📞 moveToNextSibling called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId else {
            logger.log("⚠️ No current selection, selecting initial node", category: "TreeView")
            // If in focus mode, select the focused node
            if let focusedId = viewModel.focusedNodeId {
                logger.log("🔄 Selecting focused node: \(focusedId)", category: "TreeView")
                viewModel.selectedNodeId = focusedId
            } else if let firstRoot = viewModel.getRootNodes().first {
                logger.log("🔄 Selecting first root node: \(firstRoot.id)", category: "TreeView")
                viewModel.selectedNodeId = firstRoot.id
            }
            return
        }

        // If current node is expanded and has children, go to first child
        if viewModel.expandedNodes.contains(currentId) {
            let children = viewModel.getChildren(of: currentId)
            if let firstChild = children.first {
                logger.log("🧭 Moving down to first child: \(firstChild.id)", category: "TreeView")
                viewModel.selectedNodeId = firstChild.id
                return
            }
        }

        // In focus mode, if we're on the focused node and it's collapsed, stop here
        if let focusedId = viewModel.focusedNodeId,
           currentId == focusedId,
           !viewModel.expandedNodes.contains(currentId) {
            return // Can't navigate down from collapsed focused node
        }

        // Otherwise, find next sibling or ancestor's next sibling
        var nodeId = currentId
        while let node = viewModel.allNodes.first(where: { $0.id == nodeId }) {
            let siblings = getSiblings(of: nodeId)
            if let currentIndex = siblings.firstIndex(where: { $0.id == nodeId }),
               currentIndex < siblings.count - 1 {
                let nextNode = siblings[currentIndex + 1]
                logger.log("🧭 Moving to next sibling: \(nextNode.id)", category: "TreeView")
                viewModel.selectedNodeId = nextNode.id
                return
            }

            // No next sibling, try parent's next sibling
            if let parentId = node.parentId {
                // In focus mode, don't go above the focused node
                if viewModel.focusedNodeId != nil && parentId == viewModel.focusedNodeId {
                    return // Stop at focus boundary
                }
                nodeId = parentId
            } else {
                // Reached root with no next sibling
                return
            }
        }
    }

    private func moveToPreviousSibling() {
        logger.log("📞 moveToPreviousSibling called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId else {
            logger.log("⚠️ No current selection", category: "TreeView")
            return
        }

        // Check focus boundary FIRST, before any movement
        if let focusedId = viewModel.focusedNodeId {
            if currentId == focusedId {
                // We're at the focused node - this is the upper boundary, don't move up
                return
            }
        }

        let siblings = getSiblings(of: currentId)
        if let currentIndex = siblings.firstIndex(where: { $0.id == currentId }) {
            if currentIndex > 0 {
                // Get previous sibling
                let prevSibling = siblings[currentIndex - 1]

                // If previous sibling is expanded, go to its last visible descendant
                if viewModel.expandedNodes.contains(prevSibling.id) {
                    let lastDescendant = findLastVisibleDescendant(of: prevSibling.id)
                    logger.log("🧭 Moving to last visible descendant: \(lastDescendant)", category: "TreeView")
                    viewModel.selectedNodeId = lastDescendant
                } else {
                    logger.log("🧭 Moving to previous sibling: \(prevSibling.id)", category: "TreeView")
                    viewModel.selectedNodeId = prevSibling.id
                }
            } else {
                // No previous sibling, try to go to parent
                if let node = viewModel.allNodes.first(where: { $0.id == currentId }),
                   let parentId = node.parentId {
                    logger.log("🧭 Moving up to parent: \(parentId)", category: "TreeView")
                    viewModel.selectedNodeId = parentId
                }
            }
        }
    }

    private func findLastVisibleDescendant(of nodeId: String) -> String {
        logger.log("📞 findLastVisibleDescendant called for: \(nodeId)", category: "TreeView")
        var lastId = nodeId

        // Keep going to the last child while the node is expanded
        while viewModel.expandedNodes.contains(lastId) {
            let children = viewModel.getChildren(of: lastId)
            if let lastChild = children.last {
                lastId = lastChild.id
            } else {
                break
            }
        }

        logger.log("✅ Last visible descendant found: \(lastId)", category: "TreeView")
        return lastId
    }

    private func moveToFirstChild() {
        logger.log("📞 moveToFirstChild called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId,
              let currentNode = viewModel.allNodes.first(where: { $0.id == currentId }) else {
            logger.log("⚠️ No current selection or node not found", category: "TreeView")
            return
        }

        // If it's a note node, open the note editor
        if currentNode.nodeType == "note" {
            logger.log("📝 Opening note editor for: \(currentNode.title)", category: "TreeView")
            viewModel.showingNoteEditorForNode = currentNode
            return
        }

        // Check if node has children or is expandable (smart folders always are)
        let hasChildren = !viewModel.getChildren(of: currentId).isEmpty || currentNode.nodeType == "smart_folder"

        if hasChildren {
            // If collapsed, expand it
            if !viewModel.expandedNodes.contains(currentId) {
                logger.log("🔄 Expanding node: \(currentId)", category: "TreeView")
                viewModel.expandedNodes.insert(currentId)

                // If it's a smart folder, execute its rule to populate it
                if currentNode.nodeType == "smart_folder" {
                    logger.log("🧩 Expanding smart folder: \(currentNode.title)", category: "TreeView")
                    Task {
                        await executeSmartFolderRule(for: currentNode)
                    }
                }
            } else {
                // If already expanded and not in focus mode, focus on it
                if viewModel.focusedNodeId != currentId {
                    logger.log("🎯 Right arrow focusing on expanded node: \(currentNode.title)", category: "TreeView")
                    viewModel.focusedNodeId = currentId
                    // Keep the selection on the focused node
                    viewModel.selectedNodeId = currentId
                }
            }
        }
    }

    private func moveToParent() {
        logger.log("📞 moveToParent called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId,
              let currentNode = viewModel.allNodes.first(where: { $0.id == currentId }) else {
            logger.log("⚠️ No current selection or node not found", category: "TreeView")
            return
        }

        // If node is expanded, collapse it
        if viewModel.expandedNodes.contains(currentId) {
            logger.log("🔄 Collapsing node: \(currentId)", category: "TreeView")
            viewModel.expandedNodes.remove(currentId)
            return
        }

        // If we're on the focused node in focus mode and it's collapsed
        if viewModel.focusedNodeId == currentId {
            // Move focus to parent (exit focus on this node, focus on parent)
            if let parentId = currentNode.parentId {
                logger.log("🎯 Left arrow moving focus from \(currentNode.title) to parent", category: "TreeView")
                viewModel.focusedNodeId = parentId
                viewModel.selectedNodeId = parentId
            } else {
                // If no parent, exit focus mode entirely
                logger.log("🎯 Left arrow exiting focus mode from root node", category: "TreeView")
                viewModel.focusedNodeId = nil
            }
            return
        }

        // Normal behavior - move to parent
        if let parentId = currentNode.parentId {
            logger.log("🧭 Moving to parent: \(parentId)", category: "TreeView")
            viewModel.selectedNodeId = parentId
        }
    }

    private func getSiblings(of nodeId: String) -> [Node] {
        logger.log("📞 getSiblings called for: \(nodeId)", category: "TreeView")
        guard let node = viewModel.allNodes.first(where: { $0.id == nodeId }) else {
            logger.log("⚠️ Node not found: \(nodeId)", category: "TreeView")
            return []
        }

        if let parentId = node.parentId {
            let siblings = viewModel.getChildren(of: parentId)
            logger.log("✅ Found \(siblings.count) siblings", category: "TreeView")
            return siblings
        } else {
            let roots = viewModel.getRootNodes()
            logger.log("✅ Found \(roots.count) root siblings", category: "TreeView")
            return roots
        }
    }

    private func isNodeInFocusedBranch(_ nodeId: String) -> Bool {
        guard let focusedId = viewModel.focusedNodeId else {
            return true // No focus mode, all nodes are valid
        }

        // Check if node is the focused node itself
        if nodeId == focusedId {
            return true
        }

        // Check if node is a descendant of the focused node
        var currentId = nodeId
        while let node = viewModel.allNodes.first(where: { $0.id == currentId }),
              let parentId = node.parentId {
            if parentId == focusedId {
                return true
            }
            currentId = parentId
        }

        return false
    }

    private func isNodeAboveFocused(_ nodeId: String, focusedId: String) -> Bool {
        // Check if nodeId is an ancestor of focusedId
        var currentId = focusedId
        while let node = viewModel.allNodes.first(where: { $0.id == currentId }),
              let parentId = node.parentId {
            if parentId == nodeId {
                return true
            }
            currentId = parentId
        }
        return false
    }

    private func instantiateTemplate(_ template: Node) async {
        logger.log("📞 Instantiating template: \(template.title)", category: "TreeView")

        do {
            // Generate a name for the instantiated copy
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let dateString = dateFormatter.string(from: Date())
            let name = "\(template.title) - \(dateString)"

            // Call the API to instantiate the template
            let api = APIClient.shared
            let newNode = try await api.instantiateTemplate(
                templateId: template.id,
                name: name,
                parentId: nil
            )

            logger.log("✅ Template instantiated successfully: \(newNode.title)", category: "TreeView")

            // Trigger a refresh
            await viewModel.loadAllNodes()
        } catch {
            logger.log("❌ Failed to instantiate template: \(error)", level: .error, category: "TreeView")
        }
    }

    private func executeSmartFolderRule(for node: Node) async {
        logger.log("🧩 Executing smart folder rule for: \(node.title)", category: "TreeView")
        logger.log("   Node ID: \(node.id)", category: "TreeView")
        logger.log("   Node type: \(node.nodeType)", category: "TreeView")

        // Log smart folder metadata if available
        if let smartFolderData = node.smartFolderData {
            logger.log("   Rule ID: \(smartFolderData.ruleId ?? "nil")", category: "TreeView")
            logger.log("   Auto-refresh: \(smartFolderData.autoRefresh ?? true)", category: "TreeView")
        }

        do {
            // Execute the smart folder rule via API
            logger.log("🌐 Making API call to execute smart folder...", category: "TreeView")
            let api = APIClient.shared
            let resultNodes = try await api.executeSmartFolderRule(smartFolderId: node.id)

            logger.log("✅ Smart folder executed successfully, returned \(resultNodes.count) nodes", category: "TreeView")

            // Log sample results for debugging
            for (index, node) in resultNodes.prefix(3).enumerated() {
                logger.log("   Result \(index + 1): \(node.title) (type: \(node.nodeType), id: \(node.id))", category: "TreeView")
            }
            if resultNodes.count > 3 {
                logger.log("   ... and \(resultNodes.count - 3) more nodes", category: "TreeView")
            }

            // Update UI with smart folder contents
            logger.log("📝 Updating children for smart folder", category: "TreeView")
            await MainActor.run {
                // Store the results as children of the smart folder
                viewModel.nodeChildren[node.id] = resultNodes
                logger.log("✅ UI updated with smart folder results", category: "TreeView")
            }

            logger.log("✅ Smart folder execution complete", category: "TreeView")
        } catch {
            logger.log("❌ Failed to execute smart folder rule: \(error)", level: .error, category: "TreeView")
            logger.log("   Error type: \(type(of: error))", level: .error, category: "TreeView")
            logger.log("   Error description: \(error.localizedDescription)", level: .error, category: "TreeView")
        }
    }
}

// MARK: - Subviews

private struct BreadcrumbBar: View {
    let focusedNode: Node?
    let parentChain: [Node]
    let onNodeTap: (String) -> Void
    let onExitFocus: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
                Button(action: {
                    logger.log("🔘 Breadcrumb: All Nodes clicked", category: "TreeView")
                    onExitFocus()
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                        Text("All Nodes")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                if let node = focusedNode {
                    Text("/")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    
                    ForEach(parentChain, id: \.id) { parent in
                        Button(action: {
                            logger.log("🔘 Breadcrumb: \(parent.title) clicked (id: \(parent.id))", category: "TreeView")
                            onNodeTap(parent.id)
                        }) {
                            Text(parent.title)
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        
                        Text("/")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                    
                    Text(node.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }
}

private struct TreeContent: View {
    @ObservedObject var viewModel: TreeViewModel
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    var body: some View {
        if let focusedId = viewModel.focusedNodeId,
           let focusedNode = viewModel.allNodes.first(where: { $0.id == focusedId }) {
            // Focus mode - show focused node and children
            TreeNodeView(
                node: focusedNode,
                children: viewModel.getChildren(of: focusedNode.id),
                expandedNodes: $viewModel.expandedNodes,
                selectedNodeId: $viewModel.selectedNodeId,
                focusedNodeId: $viewModel.focusedNodeId,
                nodeChildren: $viewModel.nodeChildren,
                isEditing: $viewModel.isEditing,
                showingNoteEditorForNode: $viewModel.showingNoteEditorForNode,
                getChildren: viewModel.getChildren,
                level: 0,
                isRootInFocusMode: true,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                onDelete: viewModel.deleteNode,
                onToggleTaskStatus: viewModel.toggleTaskStatus,
                onRefresh: { await viewModel.loadAllNodes() },
                onUpdateNodeTitle: viewModel.updateNodeTitle,
                onUpdateSingleNode: viewModel.updateSingleNode
            )
        } else {
            // Normal mode - show root nodes
            ForEach(viewModel.getRootNodes()) { node in
                TreeNodeView(
                    node: node,
                    children: viewModel.getChildren(of: node.id),
                    expandedNodes: $viewModel.expandedNodes,
                    selectedNodeId: $viewModel.selectedNodeId,
                    focusedNodeId: $viewModel.focusedNodeId,
                    nodeChildren: $viewModel.nodeChildren,
                    isEditing: $viewModel.isEditing,
                    showingNoteEditorForNode: $viewModel.showingNoteEditorForNode,
                    getChildren: viewModel.getChildren,
                    level: 0,
                    isRootInFocusMode: false,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    onDelete: viewModel.deleteNode,
                    onToggleTaskStatus: viewModel.toggleTaskStatus,
                    onRefresh: { await viewModel.loadAllNodes() },
                    onUpdateNodeTitle: viewModel.updateNodeTitle,
                    onUpdateSingleNode: viewModel.updateSingleNode
                )
            }
        }
    }
}

private struct TreeToolbar: ToolbarContent {
    @ObservedObject var viewModel: TreeViewModel
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @EnvironmentObject var dataManager: DataManager
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            HStack(spacing: 8) {
                // Network status indicator
                NetworkStatusIndicator(lastSyncDate: dataManager.lastSyncDate)
                
                // Refresh button
                Button(action: {
                    Task {
                        await viewModel.loadAllNodes()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
            }
            
            Menu {
                Button("Folder") {
                    viewModel.createNodeType = "folder"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }
                
                Button("Task") {
                    viewModel.createNodeType = "task"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }
                
                Button("Note") {
                    viewModel.createNodeType = "note"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }
                
                Button("Template") {
                    viewModel.createNodeType = "template"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }
                
                Button("Smart Folder") {
                    viewModel.createNodeType = "smart_folder"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }
            } label: {
                Image(systemName: "plus")
                    .imageScale(.large)
            }
        }
    }
}

// MARK: - Keyboard Shortcuts Help

private struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()

            Divider()

            // Shortcuts list
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    shortcutSection("Navigation", shortcuts: [
                        ("↑ ↓", "Navigate between sibling nodes"),
                        ("← →", "Navigate to parent/child nodes"),
                        ("Space", "Edit node name inline"),
                        ("Enter", "Save node name edit"),
                        ("Escape", "Cancel node name edit")
                    ])

                    shortcutSection("Create Nodes", shortcuts: [
                        ("T", "Create new task"),
                        ("N", "Create new note"),
                        ("F", "Create new folder")
                    ])

                    shortcutSection("Node Actions", shortcuts: [
                        (".", "Toggle task completion"),
                        ("⌘D", "Show node details"),
                        ("⌘F", "Focus on node / Execute smart folder"),
                        ("⌘T", "Manage tags"),
                        ("⌘E", "Execute smart folder"),
                        ("⌘U", "Use template"),
                        ("⌘⇧D", "Delete node")
                    ])

                    shortcutSection("Other", shortcuts: [
                        ("H", "Show this help"),
                        ("⌘R", "Refresh nodes")
                    ])
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }

    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(shortcuts, id: \.0) { shortcut, description in
                HStack {
                    Text(shortcut)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 80, alignment: .leading)
                    Text(description)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
        }
    }
}

private struct CreateNodeSheet: View {
    @ObservedObject var viewModel: TreeViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isTitleFocused: Bool
    
    private var createNodeTypeTitle: String {
        switch viewModel.createNodeType {
        case "folder": return "Folder"
        case "task": return "Task"
        case "note": return "Note"
        case "template": return "Template"
        case "smart_folder": return "Smart Folder"
        default: return "Node"
        }
    }
    
    var body: some View {
        // Compact sheet: single row with TextField on left and buttons on right
        HStack(spacing: 8) {
            TextField("", text: $viewModel.createNodeTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit {
                    Task {
                        await viewModel.createNode(
                            type: viewModel.createNodeType,
                            title: viewModel.createNodeTitle,
                            parentId: viewModel.focusedNodeId
                        )
                        dismiss()
                    }
                }

            Spacer(minLength: 8)

            Button("Cancel") { dismiss() }

            Button("Create") {
                Task {
                    await viewModel.createNode(
                        type: viewModel.createNodeType,
                        title: viewModel.createNodeTitle,
                        parentId: viewModel.focusedNodeId
                    )
                    dismiss()
                }
            }
            .disabled(viewModel.createNodeTitle.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 360, minHeight: 70)
        .onAppear {
            DispatchQueue.main.async { isTitleFocused = true }
        }
    }
}
#endif
