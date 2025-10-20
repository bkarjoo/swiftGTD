#if os(macOS)
import SwiftUI
import AppKit
import Core
import Models
import Services
import Networking

private let logger = Logger.shared

public struct TreeView_macOS: View {
    @ObservedObject var viewModel: TreeViewModel
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    @AppStorage("splitPaneThreshold") private var splitPaneThreshold = 900.0
    @AppStorage("splitPanePosition") private var splitPanePosition = 0.4 // 40% for left pane
    @AppStorage("enableSplitPane") private var enableSplitPane = true

    @State private var showingSplitPane = false
    @State private var dividerPosition: CGFloat = 0.4
    @State private var isDraggingDivider = false

    public init(viewModel: TreeViewModel? = nil) {
        self.viewModel = viewModel ?? TreeViewModel()
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let windowWidth = geometry.size.width
            let shouldShowSplitPane = enableSplitPane && windowWidth >= splitPaneThreshold

            if shouldShowSplitPane {
                // Split pane mode
                splitPaneLayout(windowWidth: windowWidth)
                    .onAppear {
                        dividerPosition = splitPanePosition
                        showingSplitPane = true
                    }
                    .onDisappear {
                        showingSplitPane = false
                    }
            } else {
                // Regular mode with popup sheets
                regularTreeView
                    .onAppear {
                        showingSplitPane = false
                    }
            }
        }
        // Common sheets that appear in both modes
        .sheet(isPresented: $viewModel.showingCreateDialog) {
            CreateNodeSheet(viewModel: viewModel)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $viewModel.showingHelpWindow) {
            KeyboardShortcutsHelpView()
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
        .alert("Drag & Drop", isPresented: $viewModel.showingDropAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.dropAlertMessage)
        }
        .alert("No Default Folder", isPresented: $viewModel.showingNoDefaultFolderAlert) {
            Button("OK") { }
        } message: {
            Text("Please set a default folder in Settings before using Quick Add (Q key).")
        }
        .sheet(isPresented: $viewModel.showingQuickAddSuccessAlert) {
            SuccessAlertSheet(message: viewModel.quickAddSuccessMessage)
        }
        .task {
            viewModel.setDataManager(dataManager)
            await viewModel.initialLoad()
        }
    }

    private func splitPaneLayout(windowWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left pane - Tree view
            treePane
                .frame(width: windowWidth * dividerPosition)

            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)
                .overlay(
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 8)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newPosition = (dividerPosition * windowWidth + value.translation.width) / windowWidth
                            dividerPosition = min(max(0.2, newPosition), 0.8) // Keep between 20% and 80%
                            splitPanePosition = dividerPosition
                        }
                        .onEnded { _ in
                            isDraggingDivider = false
                        }
                )

            // Right pane - Details/Editor
            detailPane
                .frame(width: windowWidth * (1 - dividerPosition))
        }
        // Tag picker should still show as a sheet even in split pane mode
        .sheet(item: $viewModel.showingTagPickerForNode) { node in
            TagPickerView(node: node) {
                await viewModel.updateSingleNode(nodeId: node.id)
            }
        }
        // Note editor should also be available in split pane mode
        .sheet(item: $viewModel.showingNoteEditorForNode) { node in
            NoteEditorView(node: node) {
                await viewModel.refreshNodes()
            }
        }
        // Details sheet intentionally not included - details show in right pane
    }

    private var regularTreeView: some View {
        NavigationStack {
            treePane
                .sheet(item: $viewModel.showingNoteEditorForNode) { node in
                    NoteEditorView(node: node) {
                        await viewModel.refreshNodes()
                    }
                }
                .sheet(item: $viewModel.showingDetailsForNode) { node in
                    NodeDetailsView(nodeId: node.id, treeViewModel: viewModel)
                }
                .sheet(item: $viewModel.showingTagPickerForNode) { node in
                    // ATTEMPT 8: Log when sheet is actually presented
                    let _ = logger.log("🎯 ATTEMPT 8: Tag picker sheet PRESENTING for node: \(node.title)", category: "UI-SHEET")
                    TagPickerView(node: node) {
                        await viewModel.updateSingleNode(nodeId: node.id)
                    }
                }
                .onChange(of: viewModel.showingTagPickerForNode?.id) { newId in
                    // ATTEMPT 10: Log when the binding changes
                    if let node = viewModel.showingTagPickerForNode {
                        logger.log("🔍 ATTEMPT 10: showingTagPickerForNode changed to: \(node.title)", category: "UI-BINDING")
                        logger.log("  ✅ Sheet should present now for: \(node.title)", category: "UI-BINDING")
                    } else {
                        logger.log("🔍 ATTEMPT 10: showingTagPickerForNode changed to: nil", category: "UI-BINDING")
                        logger.log("  ❌ Sheet dismissed or nil", category: "UI-BINDING")
                    }
                }
        }
    }

    private var treePane: some View {
        VStack(spacing: 0) {
            if viewModel.focusedNodeId != nil {
                BreadcrumbBar(
                    focusedNode: viewModel.focusedNode,
                    parentChain: viewModel.focusedNode.map { viewModel.getParentChain(for: $0) } ?? [],
                    onNodeTap: { nodeId in
                        viewModel.setFocusedNode(nodeId)
                    },
                    onExitFocus: {
                        viewModel.setFocusedNode(nil)
                    }
                )
            }

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
                    guard let nodeId = newNodeId else { return }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scrollProxy.scrollTo(nodeId, anchor: nil)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .navigationTitle("") // Title shown in tabs instead
    }

    private var detailPane: some View {
        Group {
            if let selectedNodeId = viewModel.selectedNodeId,
               let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedNodeId }) {
                VStack(spacing: 0) {
                    // Detail pane header
                    HStack {
                        Image(systemName: Icons.nodeIcon(for: selectedNode.nodeType))
                            .foregroundColor(Icons.nodeColor(for: selectedNode.nodeType))
                        Text(selectedNode.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Content based on node type
                    Group {
                        if selectedNode.nodeType == "note" {
                            // Embedded note editor
                            NoteEditorView(
                                node: selectedNode,
                                embeddedMode: true
                            ) {
                                await viewModel.refreshNodes()
                            }
                        } else {
                            // Node details view
                            ScrollView {
                                NodeDetailsView(
                                    nodeId: selectedNode.id,
                                    treeViewModel: viewModel,
                                    embeddedMode: true
                                )
                                .padding()
                            }
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .id(selectedNodeId) // Force view refresh when selection changes
            } else {
                // Empty state
                VStack {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a node to view details")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }


    /*  REMOVED CODE - kept for reference only
            case 2: // D key - Details
                if event.modifierFlags.contains(.shift) {
                    // // logger.log("⌨️ Cmd+Shift+D pressed - delete node", category: "TreeView")
                    if let selectedId = viewModel.selectedNodeId,
                       let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        viewModel.deleteNode(selectedNode)
                    }
                    return true
                } else {
                    // logger.log("⌨️ Cmd+D pressed - show details", category: "TreeView")
                    if let selectedId = viewModel.selectedNodeId,
                       let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        viewModel.showDetails(selectedNode)
                    }
                    return true
                }

            case 3: // F key - Focus (Cmd+Shift+F)
                if event.modifierFlags.contains(.shift) {
                    // logger.log("⌨️ Cmd+Shift+F pressed - focus on node", category: "TreeView")
                    if let selectedId = viewModel.selectedNodeId,
                       let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        if selectedNode.nodeType != "note" {
                            viewModel.focusOnNode(selectedNode)
                        }
                    }
                    return true
                }

                break

            case 17: // T key - Tags
                // logger.log("⌨️ Cmd+T pressed - show tags", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                    viewModel.showTagPicker(selectedNode)
                }
                return true

            case 14: // E key - Execute (smart folders)
                // logger.log("⌨️ Cmd+E pressed - execute smart folder", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                   selectedNode.nodeType == "smart_folder" {
                    Task {
                        await executeSmartFolderRule(for: selectedNode)
                    }
                }
                return true

            case 32: // U key - Use template
                // logger.log("⌨️ Cmd+U pressed - use template", category: "TreeView")
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                   selectedNode.nodeType == "template" {
                    Task {
                        await viewModel.instantiateTemplate(selectedNode)
                    }
                }
                return true

            default:
                break
            }
        }

        switch event.keyCode {
        case 47: // Period/Dot key - Toggle task completion
            // logger.log("⌨️ Dot pressed - toggle task", category: "TreeView")
            if let selectedId = viewModel.selectedNodeId,
               let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
               selectedNode.nodeType == "task" {
                logger.log("✅ Toggling task status for: \(selectedNode.title)", category: "TreeView")
                viewModel.toggleTaskStatus(selectedNode)
            }
            return true

        case 4: // H key - Help
            // logger.log("⌨️ H pressed - showing help", category: "TreeView")
            viewModel.showingHelpWindow = true
            return true

        case 12: // Q key - Quick add to default folder
            // logger.log("⌨️ Q pressed - quick add to default folder", category: "TreeView")
            Task {
                await handleQuickAddToDefaultFolder()
            }
            return true

        case 17 where !event.modifierFlags.contains(.command): // T key (without Cmd)
            // logger.log("⌨️ T pressed - creating new task", category: "TreeView")
            viewModel.createNodeType = "task"
            viewModel.createNodeTitle = ""
            viewModel.createNodeParentId = nil  // Clear any previous parent ID
            viewModel.showingCreateDialog = true
            return true

        case 45: // N key
            // logger.log("⌨️ N pressed - creating new note", category: "TreeView")
            viewModel.createNodeType = "note"
            viewModel.createNodeTitle = ""
            viewModel.createNodeParentId = nil  // Clear any previous parent ID
            viewModel.showingCreateDialog = true
            return true

        case 3 where !event.modifierFlags.contains(.command): // F key (without Cmd)
            // logger.log("⌨️ F pressed - creating new folder", category: "TreeView")
            viewModel.createNodeType = "folder"
            viewModel.createNodeTitle = ""
            viewModel.createNodeParentId = nil  // Clear any previous parent ID
            viewModel.showingCreateDialog = true
            return true

        case 49: // Space bar
            // logger.log("⌨️ Space bar pressed", category: "TreeView")
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
    */  // End of removed code

    // REMOVED: Local navigation methods - now handled by viewModel.navigateToNode()
    /*
    private func moveToNextSibling() {
        // logger.log("📞 moveToNextSibling called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId else {
            logger.log("⚠️ No current selection, selecting initial node", category: "TreeView")
            if let focusedId = viewModel.focusedNodeId {
                logger.log("🔄 Selecting focused node: \(focusedId)", category: "TreeView")
                viewModel.selectedNodeId = focusedId
            } else if let firstRoot = viewModel.getRootNodes().first {
                logger.log("🔄 Selecting first root node: \(firstRoot.id)", category: "TreeView")
                viewModel.selectedNodeId = firstRoot.id
            }
            return
        }

        if viewModel.expandedNodes.contains(currentId) {
            let children = viewModel.getChildren(of: currentId)
            if let firstChild = children.first {
                logger.log("🧭 Moving down to first child: \(firstChild.id)", category: "TreeView")
                viewModel.selectedNodeId = firstChild.id
                return
            }
        }

        if let focusedId = viewModel.focusedNodeId,
           currentId == focusedId,
           !viewModel.expandedNodes.contains(currentId) {
            return // Can't navigate down from collapsed focused node
        }

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

            if let parentId = node.parentId {
                if viewModel.focusedNodeId != nil && parentId == viewModel.focusedNodeId {
                    return // Stop at focus boundary
                }
                nodeId = parentId
            } else {
                return
            }
        }
    }

    private func moveToPreviousSibling() {
        // logger.log("📞 moveToPreviousSibling called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId else {
            logger.log("⚠️ No current selection", category: "TreeView")
            return
        }

        if let focusedId = viewModel.focusedNodeId {
            if currentId == focusedId {
                return
            }
        }

        let siblings = getSiblings(of: currentId)
        if let currentIndex = siblings.firstIndex(where: { $0.id == currentId }) {
            if currentIndex > 0 {
                let prevSibling = siblings[currentIndex - 1]

                if viewModel.expandedNodes.contains(prevSibling.id) {
                    let lastDescendant = findLastVisibleDescendant(of: prevSibling.id)
                    logger.log("🧭 Moving to last visible descendant: \(lastDescendant)", category: "TreeView")
                    viewModel.selectedNodeId = lastDescendant
                } else {
                    logger.log("🧭 Moving to previous sibling: \(prevSibling.id)", category: "TreeView")
                    viewModel.selectedNodeId = prevSibling.id
                }
            } else {
                if let node = viewModel.allNodes.first(where: { $0.id == currentId }),
                   let parentId = node.parentId {
                    logger.log("🧭 Moving up to parent: \(parentId)", category: "TreeView")
                    viewModel.selectedNodeId = parentId
                }
            }
        }
    }

    private func findLastVisibleDescendant(of nodeId: String) -> String {
        // logger.log("📞 findLastVisibleDescendant called for: \(nodeId)", category: "TreeView")
        var lastId = nodeId

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
        // logger.log("📞 moveToFirstChild called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId,
              let currentNode = viewModel.allNodes.first(where: { $0.id == currentId }) else {
            logger.log("⚠️ No current selection or node not found", category: "TreeView")
            return
        }

        if currentNode.nodeType == "note" {
            logger.log("📝 Opening note editor for: \(currentNode.title)", category: "TreeView")
            viewModel.openNoteEditor(currentNode)
            return
        }

        let hasChildren = !viewModel.getChildren(of: currentId).isEmpty || currentNode.nodeType == "smart_folder"

        if hasChildren {
            if !viewModel.expandedNodes.contains(currentId) {
                logger.log("🔄 Expanding node: \(currentId)", category: "TreeView")
                viewModel.expandedNodes.insert(currentId)

                if currentNode.nodeType == "smart_folder" {
                    logger.log("🧩 Expanding smart folder: \(currentNode.title)", category: "TreeView")
                    Task {
                        await executeSmartFolderRule(for: currentNode)
                    }
                }
            } else {
                if viewModel.focusedNodeId != currentId {
                    logger.log("🎯 Right arrow focusing on expanded node: \(currentNode.title)", category: "TreeView")
                    // Use selectAndFocus composite method instead of separate calls
                    viewModel.selectAndFocus(currentId)
                }
            }
        } else {
            // Node has no children - still focus it
            if viewModel.focusedNodeId != currentId {
                logger.log("🎯 Right arrow focusing on node without children: \(currentNode.title)", category: "TreeView")
                // Use selectAndFocus composite method instead of separate calls
                viewModel.selectAndFocus(currentId)
            }
        }
    }

    private func moveToParent() {
        // logger.log("📞 moveToParent called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId,
              let currentNode = viewModel.allNodes.first(where: { $0.id == currentId }) else {
            logger.log("⚠️ No current selection or node not found", category: "TreeView")
            return
        }

        if viewModel.expandedNodes.contains(currentId) {
            logger.log("🔄 Collapsing node: \(currentId)", category: "TreeView")
            viewModel.expandedNodes.remove(currentId)
            return
        }

        if viewModel.focusedNodeId == currentId {
            if let parentId = currentNode.parentId {
                logger.log("🎯 Left arrow moving focus from \(currentNode.title) to parent", category: "TreeView")
                viewModel.setFocusedNode(parentId)
                // Keep selection on current node, don't move it to parent
            } else {
                logger.log("🎯 Left arrow exiting focus mode from root node", category: "TreeView")
                viewModel.setFocusedNode(nil)
                // Keep selection on current node
            }
            return
        }

        if let parentId = currentNode.parentId {
            logger.log("🧭 Moving to parent: \(parentId)", category: "TreeView")
            viewModel.selectedNodeId = parentId
        }
    }

    private func getSiblings(of nodeId: String) -> [Node] {
        // logger.log("📞 getSiblings called for: \(nodeId)", category: "TreeView")
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
    */  // End of removed navigation methods

    private func isNodeInFocusedBranch(_ nodeId: String) -> Bool {
        guard let focusedId = viewModel.focusedNodeId else {
            return true // No focus mode, all nodes are valid
        }

        if nodeId == focusedId {
            return true
        }

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


    private func handleQuickAddToDefaultFolder() async {
        // Get the default folder ID
        guard let defaultNodeId = await dataManager.getDefaultFolder() else {
            logger.log("⚠️ No default folder set", category: "TreeView", level: .warning)
            // Could show an alert here if desired
            return
        }

            // Find the default folder in the current nodes
            guard let defaultFolder = viewModel.allNodes.first(where: { $0.id == defaultNodeId }) else {
                logger.log("⚠️ Default folder not found in nodes", category: "TreeView", level: .warning)
                return
            }

            logger.log("✅ Quick add to default folder: \(defaultFolder.title)", category: "TreeView")

            // Set up for creating a task in the default folder
            viewModel.createNodeType = "task"
            viewModel.createNodeTitle = ""
            viewModel.createNodeParentId = defaultNodeId  // Set the explicit parent ID

            // Show the create dialog
            viewModel.showingCreateDialog = true
    }

    private func copyNodeNamesToClipboard() {
        logger.log("📋 Copying node names to clipboard", category: "TreeView")

        var textToCopy = ""

        // Get the nodes to copy based on focus state
        if let focusedId = viewModel.focusedNodeId {
            // In focus mode - copy the focused node and its direct children
            if let focusedNode = viewModel.allNodes.first(where: { $0.id == focusedId }) {
                textToCopy = focusedNode.title + "\n"

                // Get direct children only (not nested)
                let children = viewModel.getChildren(of: focusedId)
                for child in children {
                    textToCopy += "- " + child.title + "\n"
                }
            }
        } else {
            // Not in focus mode - copy all root nodes
            textToCopy = "All Nodes\n"
            let rootNodes = viewModel.getRootNodes()
            for node in rootNodes {
                textToCopy += "- " + node.title + "\n"
            }
        }

        // Copy to clipboard
        if !textToCopy.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            logger.log("✅ Copied \(textToCopy.components(separatedBy: "\n").count - 1) node names to clipboard", category: "TreeView")
        }
    }

    private func executeSmartFolderRule(for node: Node) async {
        logger.log("🧩 Executing smart folder rule for: \(node.title)", category: "TreeView")
        logger.log("   Node ID: \(node.id)", category: "TreeView")
        logger.log("   Node type: \(node.nodeType)", category: "TreeView")

        if let smartFolderData = node.smartFolderData {
            logger.log("   Rule ID: \(smartFolderData.ruleId ?? "nil")", category: "TreeView")
            logger.log("   Auto-refresh: \(smartFolderData.autoRefresh ?? true)", category: "TreeView")
        }

        logger.log("🌐 Executing smart folder via DataManager...", category: "TreeView")
        let resultNodes = await dataManager.executeSmartFolder(nodeId: node.id)

        if !resultNodes.isEmpty {
            logger.log("📝 Updating children for smart folder with \(resultNodes.count) nodes", category: "TreeView")
            await MainActor.run {
                viewModel.nodeChildren[node.id] = resultNodes
                logger.log("✅ UI updated with smart folder results", category: "TreeView")
            }

            logger.log("✅ Smart folder execution complete", category: "TreeView")
        } else {
            logger.log("⚠️ Smart folder returned no results", category: "TreeView")
        }
    }
}


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
                chevronPosition: .leading,
                onDelete: viewModel.deleteNode,
                onToggleTaskStatus: viewModel.toggleTaskStatus,
                onRefresh: { await viewModel.refreshNodes() },
                onUpdateNodeTitle: viewModel.updateNodeTitle,
                onUpdateSingleNode: viewModel.updateSingleNode,
                onNodeDrop: viewModel.performReorder,
                onExecuteSmartFolder: viewModel.executeSmartFolder,
                onInstantiateTemplate: viewModel.instantiateTemplate,
                onCollapseNode: viewModel.collapseNode,
                onFocusNode: viewModel.focusOnNode,
                onOpenNoteEditor: viewModel.openNoteEditor,
                onShowTagPicker: viewModel.showTagPicker,
                onShowDetails: viewModel.showDetails,
                getRootNodes: viewModel.getRootNodes
            )
        } else {
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
                    chevronPosition: .leading,
                    onDelete: viewModel.deleteNode,
                    onToggleTaskStatus: viewModel.toggleTaskStatus,
                    onRefresh: { await viewModel.refreshNodes() },
                    onUpdateNodeTitle: viewModel.updateNodeTitle,
                    onUpdateSingleNode: viewModel.updateSingleNode,
                    onNodeDrop: viewModel.performReorder,
                    onExecuteSmartFolder: viewModel.executeSmartFolder,
                    onInstantiateTemplate: viewModel.instantiateTemplate,
                    onCollapseNode: viewModel.collapseNode,
                    onFocusNode: viewModel.focusOnNode,
                    onOpenNoteEditor: viewModel.openNoteEditor,
                    onShowTagPicker: viewModel.showTagPicker,
                    onShowDetails: viewModel.showDetails,
                    getRootNodes: viewModel.getRootNodes
                )
            }
        }
    }
}

public struct TreeToolbar: ToolbarContent {
    @ObservedObject var viewModel: TreeViewModel
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @EnvironmentObject var dataManager: DataManager

    public init(viewModel: TreeViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            HStack(spacing: 8) {
                NetworkStatusIndicator(lastSyncDate: dataManager.lastSyncDate)

                Button(action: {
                    viewModel.showCompletedTasks.toggle()
                }) {
                    Image(systemName: viewModel.showCompletedTasks ? "eye" : "eye.slash")
                }
                .help(viewModel.showCompletedTasks ? "Hide completed tasks" : "Show completed tasks")

                Button(action: {
                    Task {
                        await viewModel.refreshNodes()
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
                    viewModel.createNodeParentId = nil  // Clear any previous parent ID
                    viewModel.showingCreateDialog = true
                }
                
                Button("Task") {
                    viewModel.createNodeType = "task"
                    viewModel.createNodeTitle = ""
                    viewModel.createNodeParentId = nil  // Clear any previous parent ID
                    viewModel.showingCreateDialog = true
                }
                
                Button("Note") {
                    viewModel.createNodeType = "note"
                    viewModel.createNodeTitle = ""
                    viewModel.createNodeParentId = nil  // Clear any previous parent ID
                    viewModel.showingCreateDialog = true
                }
                
                Button("Template") {
                    viewModel.createNodeType = "template"
                    viewModel.createNodeTitle = ""
                    viewModel.createNodeParentId = nil  // Clear any previous parent ID
                    viewModel.showingCreateDialog = true
                }
                
                Button("Smart Folder") {
                    viewModel.createNodeType = "smart_folder"
                    viewModel.createNodeTitle = ""
                    viewModel.createNodeParentId = nil  // Clear any previous parent ID
                    viewModel.showingCreateDialog = true
                }
            } label: {
                Image(systemName: "plus")
                    .imageScale(.large)
            }
        }
    }
}


private struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
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
                        ("⌘C", "Copy node names to clipboard"),
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

public struct CreateNodeSheet: View {
    @ObservedObject var viewModel: TreeViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isTitleFocused: Bool
    @State private var isSubmitting = false

    public init(viewModel: TreeViewModel) {
        self.viewModel = viewModel
    }

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

    public var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Create New \(createNodeTypeTitle)")
                .font(.headline)
                .padding(.top, 4)

            // Input field
            TextField(fieldPlaceholder, text: $viewModel.createNodeTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit {
                    if !isSubmitting {
                        submit()
                    }
                }
                .frame(minWidth: 300)

            // Divider + buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    if !isSubmitting {
                        submit()
                    }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.createNodeTitle.isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onAppear { DispatchQueue.main.async { isTitleFocused = true } }
    }

    private var fieldPlaceholder: String {
        switch viewModel.createNodeType {
        case "note": return "Note Title"
        case "task": return "Task Name"
        case "folder": return "Folder Name"
        case "template": return "Template Name"
        case "smart_folder": return "Smart Folder Name"
        default: return "Title"
        }
    }

    private func submit() {
        guard !viewModel.createNodeTitle.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        Task {
            // Determine parent ID based on selection and expanded state
            let parentId: String?

            if let explicitParentId = viewModel.createNodeParentId {
                // Use explicit parent ID if set (e.g., for quick add via Q key)
                parentId = explicitParentId
            } else if let selectedId = viewModel.selectedNodeId {
                // Check if the selected node is expanded
                if viewModel.expandedNodes.contains(selectedId) {
                    // Node is expanded → new node becomes a child
                    parentId = selectedId
                } else {
                    // Node is collapsed → new node becomes a sibling
                    // Find the selected node's parent
                    if let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        parentId = selectedNode.parentId
                    } else {
                        parentId = nil
                    }
                }
            } else {
                // No selection → create at root level
                parentId = nil
            }

            await viewModel.createNode(
                type: viewModel.createNodeType,
                title: viewModel.createNodeTitle,
                parentId: parentId
            )
            // Clear the createNodeParentId after use
            viewModel.createNodeParentId = nil
            dismiss()
        }
    }
}

public struct SuccessAlertSheet: View {
    let message: String
    @Environment(\.dismiss) var dismiss
    @State private var keyEventMonitor: Any?
    @State private var shouldDismiss = false

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Task Added")
                .font(.headline)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)

            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.return)
        }
        .padding(30)
        .frame(minWidth: 300)
        .onAppear {
            // Monitor for Enter/Return/Escape keys
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 53 {
                    // 36 = Return, 76 = Enter, 53 = Escape
                    DispatchQueue.main.async {
                        shouldDismiss = true
                    }
                    return nil
                }
                return event
            }
        }
        .onChange(of: shouldDismiss) { newValue in
            if newValue {
                dismiss()
            }
        }
        .onDisappear {
            if let monitor = keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyEventMonitor = nil
            }
        }
    }
}
#endif
