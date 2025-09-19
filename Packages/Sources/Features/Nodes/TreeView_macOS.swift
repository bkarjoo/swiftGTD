#if os(macOS)
import SwiftUI
import AppKit
import Core
import Models
import Services
import Networking

private let logger = Logger.shared

private struct IsInTabbedViewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInTabbedView: Bool {
        get { self[IsInTabbedViewKey.self] }
        set { self[IsInTabbedViewKey.self] = newValue }
    }
}

public struct TreeView_macOS: View {
    @ObservedObject var viewModel: TreeViewModel
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    @FocusState private var isTreeFocused: Bool
    @State private var keyEventMonitor: Any?
    @Environment(\.isInTabbedView) private var isInTabbedView

    public init(viewModel: TreeViewModel? = nil) {
        self.viewModel = viewModel ?? TreeViewModel()
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                .background(alignment: .topLeading) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .focusable()
                        .focused($isTreeFocused)
                        .accessibilityHidden(true)
                }
                .onTapGesture {
                    if !isTreeFocused {
                        logger.log("🎯 Setting focus via tap gesture", category: "TreeView")
                        isTreeFocused = true
                    }
                }
                .onChange(of: viewModel.isEditing) { isEditing in
                    if !isEditing {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            logger.log("🎯 Restoring focus to tree after editing", category: "TreeView")
                            self.isTreeFocused = true
                        }
                    }
                }
                .onMoveCommand { direction in
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
                    if !isInTabbedView {
                        setupKeyEventMonitor()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        logger.log("🎯 Setting initial focus to tree view", category: "TreeView")
                        self.isTreeFocused = true
                        if let window = NSApp.keyWindow {
                            window.makeKey()
                            window.makeFirstResponder(window.contentView)
                        }
                    }
                }
                .onDisappear {
                    if !isInTabbedView {
                        if let monitor = keyEventMonitor {
                            NSEvent.removeMonitor(monitor)
                            keyEventMonitor = nil
                        }
                    }
                }
            }
            .navigationTitle(isInTabbedView ? "" : (viewModel.currentFocusedNode?.title ?? "All Nodes"))
            .toolbar {
                if !isInTabbedView {
                    TreeToolbar(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $viewModel.showingCreateDialog) {
                if !isInTabbedView {
                    CreateNodeSheet(viewModel: viewModel)
                        .environmentObject(dataManager)
                }
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
                    await viewModel.updateSingleNode(nodeId: node.id)
                }
            }
            .sheet(isPresented: $viewModel.showingHelpWindow) {
                KeyboardShortcutsHelpView()
            }
            .onChange(of: viewModel.showingNoteEditorForNode != nil) { isShowing in
                if !isInTabbedView {
                    if isShowing {
                        if let monitor = keyEventMonitor {
                            NSEvent.removeMonitor(monitor)
                            keyEventMonitor = nil
                        }
                    } else {
                        setupKeyEventMonitor()
                    }
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
                viewModel.setDataManager(dataManager)
                await viewModel.loadAllNodes()

                // Only set initial selection if not in tabbed view and no focus/selection exists
                if !isInTabbedView && viewModel.focusedNodeId == nil && viewModel.selectedNodeId == nil {
                    if let firstRoot = viewModel.getRootNodes().first {
                        logger.log("🎯 Setting initial selection to first root: \(firstRoot.id)", category: "TreeView")
                        viewModel.selectedNodeId = firstRoot.id
                    }
                } else {
                    logger.log("⏭️ Skipping initial selection (isInTabbedView: \(isInTabbedView), focusedNodeId: \(viewModel.focusedNodeId ?? "nil"), selectedNodeId: \(viewModel.selectedNodeId ?? "nil"))", category: "TreeView")
                }
            }
        }
    }

    private func setupKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if !self.isTreeFocused {
                return event
            }

            if self.viewModel.showingDeleteAlert && event.keyCode == 53 { // Escape key
                logger.log("⌨️ Escape pressed - closing delete alert", category: "TreeView")
                self.viewModel.showingDeleteAlert = false
                self.viewModel.nodeToDelete = nil
                return nil // Consume the event
            }

            if viewModel.showingDeleteAlert ||
               viewModel.showingCreateDialog ||
               viewModel.showingDetailsForNode != nil ||
               viewModel.showingTagPickerForNode != nil ||
               viewModel.showingHelpWindow {
                return event
            }

            if let firstResponder = NSApp.keyWindow?.firstResponder {
                if firstResponder is NSTextView || firstResponder is NSTextField {
                    return event
                }
            }

            return self.handleKeyEvent(event) ? nil : event
        }
        logger.log("✅ Key event monitor setup complete", category: "TreeView")
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 2: // D key - Details
                if event.modifierFlags.contains(.shift) {
                    logger.log("⌨️ Cmd+Shift+D pressed - delete node", category: "TreeView")
                    if let selectedId = viewModel.selectedNodeId,
                       let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                        viewModel.deleteNode(selectedNode)
                    }
                    return true
                } else {
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
                        logger.log("🧩 Smart folder detected, focusing and executing rule", category: "TreeView")
                        viewModel.focusedNodeId = selectedNode.id
                        viewModel.expandedNodes.insert(selectedNode.id)
                        Task {
                            await executeSmartFolderRule(for: selectedNode)
                        }
                    } else if selectedNode.nodeType != "note" {
                        viewModel.focusedNodeId = selectedNode.id
                        viewModel.expandedNodes.insert(selectedNode.id)
                    }
                    NotificationCenter.default.post(name: .focusChanged, object: nil)
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
        logger.log("📞 moveToPreviousSibling called", category: "TreeView")
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
        logger.log("📞 findLastVisibleDescendant called for: \(nodeId)", category: "TreeView")
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
        logger.log("📞 moveToFirstChild called", category: "TreeView")
        guard let currentId = viewModel.selectedNodeId,
              let currentNode = viewModel.allNodes.first(where: { $0.id == currentId }) else {
            logger.log("⚠️ No current selection or node not found", category: "TreeView")
            return
        }

        if currentNode.nodeType == "note" {
            logger.log("📝 Opening note editor for: \(currentNode.title)", category: "TreeView")
            viewModel.showingNoteEditorForNode = currentNode
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
                    viewModel.focusedNodeId = currentId
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

        if viewModel.expandedNodes.contains(currentId) {
            logger.log("🔄 Collapsing node: \(currentId)", category: "TreeView")
            viewModel.expandedNodes.remove(currentId)
            return
        }

        if viewModel.focusedNodeId == currentId {
            if let parentId = currentNode.parentId {
                logger.log("🎯 Left arrow moving focus from \(currentNode.title) to parent", category: "TreeView")
                viewModel.focusedNodeId = parentId
                viewModel.selectedNodeId = parentId
            } else {
                logger.log("🎯 Left arrow exiting focus mode from root node", category: "TreeView")
                viewModel.focusedNodeId = nil
            }
            return
        }

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

    private func instantiateTemplate(_ template: Node) async {
        logger.log("📞 Instantiating template: \(template.title)", category: "TreeView")

        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let dateString = dateFormatter.string(from: Date())
            let name = "\(template.title) - \(dateString)"

            let api = APIClient.shared
            let newNode = try await api.instantiateTemplate(
                templateId: template.id,
                name: name,
                parentId: nil
            )

            logger.log("✅ Template instantiated successfully: \(newNode.title)", category: "TreeView")

            await viewModel.loadAllNodes()
        } catch {
            logger.log("❌ Failed to instantiate template: \(error)", level: .error, category: "TreeView")
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

        do {
            logger.log("🌐 Making API call to execute smart folder...", category: "TreeView")
            let api = APIClient.shared
            let resultNodes = try await api.executeSmartFolderRule(smartFolderId: node.id)

            logger.log("✅ Smart folder executed successfully, returned \(resultNodes.count) nodes", category: "TreeView")

            for (index, node) in resultNodes.prefix(3).enumerated() {
                logger.log("   Result \(index + 1): \(node.title) (type: \(node.nodeType), id: \(node.id))", category: "TreeView")
            }
            if resultNodes.count > 3 {
                logger.log("   ... and \(resultNodes.count - 3) more nodes", category: "TreeView")
            }

            logger.log("📝 Updating children for smart folder", category: "TreeView")
            await MainActor.run {
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
                onDelete: viewModel.deleteNode,
                onToggleTaskStatus: viewModel.toggleTaskStatus,
                onRefresh: { await viewModel.loadAllNodes() },
                onUpdateNodeTitle: viewModel.updateNodeTitle,
                onUpdateSingleNode: viewModel.updateSingleNode
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
                .onSubmit { submit() }
                .frame(minWidth: 300)

            // Divider + buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.createNodeTitle.isEmpty)
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
        guard !viewModel.createNodeTitle.isEmpty else { return }
        Task {
            await viewModel.createNode(
                type: viewModel.createNodeType,
                title: viewModel.createNodeTitle,
                parentId: viewModel.focusedNodeId
            )
            dismiss()
        }
    }
}
#endif
