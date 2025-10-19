import SwiftUI
import Core
import Models
import Services
import Networking
import UniformTypeIdentifiers

private let logger = Logger.shared

public enum DropPosition {
    case none
    case above
    case below
    case inside  // Drop as child of target node
}

public enum ChevronPosition {
    case leading
    case trailing
}

public struct TreeNodeView: View {
    let node: Node
    let children: [Node]
    @Binding var expandedNodes: Set<String>
    @Binding var selectedNodeId: String?
    @Binding var focusedNodeId: String?
    @Binding var nodeChildren: [String: [Node]]
    @Binding var isEditing: Bool
    @Binding var showingNoteEditorForNode: Node?
    let getChildren: (String) -> [Node]
    let level: Int
    let isRootInFocusMode: Bool
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let chevronPosition: ChevronPosition  // Default provided in init
    let onDelete: (Node) -> Void
    let onToggleTaskStatus: (Node) -> Void
    let onRefresh: () async -> Void
    let onUpdateNodeTitle: (String, String) async -> Void
    let onUpdateSingleNode: (String) async -> Void
    let onNodeDrop: ((Node, Node, DropPosition, String) async -> Void)?  // Pass nodes, position, and message
    let onExecuteSmartFolder: ((Node) async -> Void)?  // Execute smart folder
    let onInstantiateTemplate: ((Node) async -> Void)?  // Instantiate template
    let onCollapseNode: ((String) -> Void)?  // Collapse node with proper selection handling
    let onFocusNode: ((Node) -> Void)?  // Focus on node (unified method)
    let onOpenNoteEditor: ((Node) -> Void)?  // Open note editor (unified method)
    let onShowTagPicker: ((Node) -> Void)?  // Show tag picker (unified method)
    let onShowDetails: ((Node) -> Void)?  // Show details (unified method)
    let getRootNodes: (() -> [Node])?  // Get root nodes for drag and drop

    @State private var showingDetailsForNode: Node?
    // ATTEMPT 11: Removed local showingTagPickerForNode - use ViewModel's instead
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var dropTargetPosition: DropPosition = .none
    @State private var rowHeight: CGFloat = 0

    // Public initializer with platform-aware default for chevronPosition
    public init(
        node: Node,
        children: [Node],
        expandedNodes: Binding<Set<String>>,
        selectedNodeId: Binding<String?>,
        focusedNodeId: Binding<String?>,
        nodeChildren: Binding<[String: [Node]]>,
        isEditing: Binding<Bool>,
        showingNoteEditorForNode: Binding<Node?>,
        getChildren: @escaping (String) -> [Node],
        level: Int,
        isRootInFocusMode: Bool,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        chevronPosition: ChevronPosition = {
            #if os(iOS)
            return .trailing
            #else
            return .leading
            #endif
        }(),
        onDelete: @escaping (Node) -> Void,
        onToggleTaskStatus: @escaping (Node) -> Void,
        onRefresh: @escaping () async -> Void,
        onUpdateNodeTitle: @escaping (String, String) async -> Void,
        onUpdateSingleNode: @escaping (String) async -> Void,
        onNodeDrop: ((Node, Node, DropPosition, String) async -> Void)? = nil,
        onExecuteSmartFolder: ((Node) async -> Void)? = nil,
        onInstantiateTemplate: ((Node) async -> Void)? = nil,
        onCollapseNode: ((String) -> Void)? = nil,
        onFocusNode: ((Node) -> Void)? = nil,
        onOpenNoteEditor: ((Node) -> Void)? = nil,
        onShowTagPicker: ((Node) -> Void)? = nil,
        onShowDetails: ((Node) -> Void)? = nil,
        getRootNodes: (() -> [Node])? = nil
    ) {
        self.node = node
        self.children = children
        self._expandedNodes = expandedNodes
        self._selectedNodeId = selectedNodeId
        self._focusedNodeId = focusedNodeId
        self._nodeChildren = nodeChildren
        self._isEditing = isEditing
        self._showingNoteEditorForNode = showingNoteEditorForNode
        self.getChildren = getChildren
        self.level = level
        self.isRootInFocusMode = isRootInFocusMode
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.chevronPosition = chevronPosition
        self.onDelete = onDelete
        self.onToggleTaskStatus = onToggleTaskStatus
        self.onRefresh = onRefresh
        self.onUpdateNodeTitle = onUpdateNodeTitle
        self.onUpdateSingleNode = onUpdateSingleNode
        self.onNodeDrop = onNodeDrop
        self.onExecuteSmartFolder = onExecuteSmartFolder
        self.onInstantiateTemplate = onInstantiateTemplate
        self.onCollapseNode = onCollapseNode
        self.onFocusNode = onFocusNode
        self.onOpenNoteEditor = onOpenNoteEditor
        self.onShowTagPicker = onShowTagPicker
        self.onShowDetails = onShowDetails
        self.getRootNodes = getRootNodes
    }

    private var isExpanded: Bool {
        expandedNodes.contains(node.id)
    }
    
    private var hasChildren: Bool {
        // Note nodes never have children
        if node.nodeType == "note" {
            return false
        }
        // Smart folders always show chevron to allow loading contents
        if node.nodeType == "smart_folder" {
            return true
        }
        // Check if we actually have children in our local data
        return !children.isEmpty
    }
    
    private var nodeIcon: String {
        switch node.nodeType {
        case "folder": return "folder"
        case "task": return isCompleted ? "checkmark.circle.fill" : "circle"
        case "note": return "note.text"
        case "project": return "star"
        case "area": return "tray.full"
        case "smart_folder": return "sparkles"
        case "template": return "doc.text"
        default: return "doc"
        }
    }
    
    private var nodeIconColor: Color {
        switch node.nodeType {
        case "folder": return .blue
        case "task": return isCompleted ? .blue : .gray
        case "note": return .orange
        case "project": return .purple
        case "area": return .indigo
        case "smart_folder": return .pink
        case "template": return .brown
        default: return .gray
        }
    }
    
    private var isCompleted: Bool {
        node.taskData?.status == "done" || node.taskData?.status == "completed"
    }

    private var backgroundColorForState: Color {
        if dropTargetPosition == .inside {
            return Color.blue.opacity(0.15)  // Highlight for "drop inside"
        } else if selectedNodeId == node.id {
            return Color.gray.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drop indicator line above
            if dropTargetPosition == .above {
                Rectangle()
                    .fill(Color.blue)
                    .frame(height: 2)
                    .padding(.leading, CGFloat(level * 20))
            }

            // Create the main row content
            nodeRowContent
                .id(node.id)  // Add ID for ScrollViewReader to find this node
                .contentShape(Rectangle()) // Make entire row tappable
                .onDrop(of: [UTType.data], delegate: NodeDropDelegate(
                    targetNode: node,
                    parentId: node.parentId,
                    dropPosition: $dropTargetPosition,
                    onDrop: handleDrop,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    rowHeight: rowHeight
                ))
                // Measure the actual rendered height of the row for accurate drop zones
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: RowHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(RowHeightPreferenceKey.self) { value in
                    rowHeight = value
                }
                #if os(macOS)
                .contextMenu {
                    Button(action: {
                        logger.log("🔘 Details selected for node: \(node.id) - \(node.title)", category: "TreeNodeView")

                        // SMART FOLDER RULE 3: Context menu "Execute" action for smart folders
                        if node.nodeType == "smart_folder" {
                            logger.log("🧩 Node is smart folder, executing rule instead of showing details", category: "TreeNodeView")
                            Task {
                                await executeSmartFolderRule()
                            }
                        } else {
                            logger.log("📄 Showing details for regular node", category: "TreeNodeView")
                            if let onShowDetails = onShowDetails {
                                onShowDetails(node)
                            } else {
                                showingDetailsForNode = node
                            }
                        }
                    }) {
                        Label(node.nodeType == "smart_folder" ? "Execute" : "Details",
                              systemImage: node.nodeType == "smart_folder" ? "play.circle" : "info.circle")
                    }
                    
                    // Note nodes don't have focus mode
                    if node.nodeType != "note" {
                        Button(action: {
                            // logger.log("🔘 Focus button clicked for node: \(node.id)", category: "TreeNodeView")
                            // Always route through the view model's focusOnNode method
                            if let onFocusNode = onFocusNode {
                                onFocusNode(node)
                            } else {
                                // This should not happen in practice as the callback is always provided
                                assertionFailure("onFocusNode callback not provided")
                            }
                        }) {
                            Label("Focus", systemImage: "arrow.right.circle")
                        }
                    }
                    
                    Divider()

                    // SMART FOLDER RULE 2: Cannot tag smart folders
                    // Smart folders are virtual containers and don't support tags
                    if node.nodeType != "smart_folder" {
                        Button(action: {
                            logger.log("🔘 Tags selected for node: \(node.id) - \(node.title)", category: "TreeNodeView")
                            // ATTEMPT 11: Always use callback, no local state fallback
                            if let onShowTagPicker = onShowTagPicker {
                                onShowTagPicker(node)
                            } else {
                                logger.log("⚠️ ATTEMPT 11: No onShowTagPicker callback provided!", category: "TreeNodeView")
                            }
                        }) {
                            Label("Tags", systemImage: "tag")
                        }
                    }
                    
                    // Template-specific action: Instantiate
                    if node.nodeType == "template" {
                        Divider()
                        
                        Button(action: {
                            logger.log("🔘 Instantiate template selected for: \(node.id) - \(node.title)", category: "TreeNodeView")
                            Task {
                                await instantiateTemplate(node)
                            }
                        }) {
                            Label("Use Template", systemImage: "doc.on.doc")
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        // logger.log("🔘 Delete button clicked for node: \(node.id)", category: "TreeNodeView")
                        onDelete(node)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                #endif

            // Drop indicator line below
            if dropTargetPosition == .below {
                Rectangle()
                    .fill(Color.blue)
                    .frame(height: 2)
                    .padding(.leading, CGFloat(level * 20))
            }

            // Children (recursive)
            if isExpanded {
                ForEach(children) { childNode in
                    TreeNodeView(
                        node: childNode,
                        children: getChildren(childNode.id),
                        expandedNodes: $expandedNodes,
                        selectedNodeId: $selectedNodeId,
                        focusedNodeId: $focusedNodeId,
                        nodeChildren: $nodeChildren,
                        isEditing: $isEditing,
                        showingNoteEditorForNode: $showingNoteEditorForNode,
                        getChildren: getChildren,
                        level: isRootInFocusMode ? 0 : level + 1,
                        isRootInFocusMode: false,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        chevronPosition: chevronPosition,
                        onDelete: onDelete,
                        onToggleTaskStatus: onToggleTaskStatus,
                        onRefresh: onRefresh,
                        onUpdateNodeTitle: onUpdateNodeTitle,
                        onUpdateSingleNode: onUpdateSingleNode,
                        onNodeDrop: onNodeDrop,
                        onExecuteSmartFolder: onExecuteSmartFolder,
                        onInstantiateTemplate: onInstantiateTemplate,
                        onCollapseNode: onCollapseNode,
                        onFocusNode: onFocusNode,
                        onOpenNoteEditor: onOpenNoteEditor,
                        onShowTagPicker: onShowTagPicker,
                        onShowDetails: onShowDetails
                    )
                }
            }
        }
        .sheet(item: $showingDetailsForNode) { node in
            NodeDetailsView(nodeId: node.id, treeViewModel: nil)
        }
        // ATTEMPT 11: Removed duplicate sheet for tag picker - handled at TreeView_macOS level
        .sheet(item: $showingNoteEditorForNode) { node in
            NoteEditorView(node: node) {
                // Refresh to show updated note
                await onRefresh()
            }
        }
    }
    
    @ViewBuilder
    private var nodeRowContent: some View {
        HStack(spacing: 4) {
            // Indentation (not for root in focus mode)
            if !isRootInFocusMode {
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }
            }

            // Expand/collapse chevron (leading position) - not draggable
            if chevronPosition == .leading {
                chevronButton
            }

            // Middle content with drag-and-drop - chevron excluded from draggable area
            draggableContent

            // Expand/collapse chevron (trailing position) - not draggable
            if chevronPosition == .trailing {
                chevronButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, lineSpacing)
        .background(backgroundColorForState)
        .overlay(
            // Add border for "drop inside" state
            RoundedRectangle(cornerRadius: 4)
                .stroke(dropTargetPosition == .inside ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    // PreferenceKey to capture row height
    struct RowHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat { 0 }
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @ViewBuilder
    private var draggableContent: some View {
        HStack(spacing: 4) {
            // Node icon - clickable behavior depends on node type
            Button(action: {
                if node.nodeType == "task" {
                    // For tasks, toggle completion status
                    // logger.log("🔘 Task checkbox clicked for node: \(node.id) - \(node.title)", category: "TreeNodeView")
                    logger.log("Current completion status: \(node.taskData?.completedAt != nil)", category: "TreeNodeView")
                    onToggleTaskStatus(node)
                    logger.log("✅ onToggleTaskStatus called", category: "TreeNodeView")
                } else if node.nodeType == "folder" {
                    // For folders, use unified click behavior
                    handleFolderClick()
                } else if hasChildren {
                    // For other non-task nodes with children, toggle expand/collapse
                    // logger.log("🔽 Icon clicked for node: \(node.title) (type: \(node.nodeType))", category: "TreeNodeView")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            // logger.log("📦 Collapsing node via icon: \(node.title)", category: "TreeNodeView")
                            if let onCollapseNode = onCollapseNode {
                                onCollapseNode(node.id)
                            } else {
                                expandedNodes.remove(node.id)
                            }
                        } else {
                            // logger.log("📤 Expanding node via icon: \(node.title)", category: "TreeNodeView")
                            expandedNodes.insert(node.id)
                            // SMART FOLDER RULE 3: Execute rule when expanding via icon
                            if node.nodeType == "smart_folder" {
                                // logger.log("🧩 Smart folder detected on expand via icon, executing rule", category: "TreeNodeView")
                                Task {
                                    await executeSmartFolderRule()
                                }
                            }
                        }
                    }
                }
            }) {
                Image(systemName: nodeIcon)
                    .font(.system(size: fontSize))
                    .foregroundColor(nodeIconColor)
                    .frame(width: fontSize + 6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(node.nodeType != "task" && !hasChildren)

            // Node title - clickable to focus (or open note editor for notes)
            if isEditing && selectedNodeId == node.id {
                TextField("", text: $editingText, onCommit: {
                    // Save the edited title when Enter is pressed
                    if editingText != node.title && !editingText.isEmpty {
                        logger.log("💾 Saving node title: \(node.id) from '\(node.title)' to '\(editingText)'", category: "TreeNodeView")
                        Task {
                            await onUpdateNodeTitle(node.id, editingText)
                        }
                    }
                    isEditing = false
                    isTextFieldFocused = false
                })
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: fontSize))
                .focused($isTextFieldFocused)
                .onAppear {
                    editingText = node.title
                }
                .task {
                    // Use task to set focus, which is more SwiftUI-idiomatic
                    isTextFieldFocused = true
                }
                #if os(macOS)
                .onExitCommand {
                    // Cancel editing and revert to original title when Escape is pressed
                    logger.log("🔙 Canceling node edit, reverting to: \(node.title)", category: "TreeNodeView")
                    editingText = node.title
                    isEditing = false
                    isTextFieldFocused = false
                }
                #endif
            } else {
                Text(node.title)
                    .font(.system(size: fontSize))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .overlay(
                        Color.white.opacity(0.001) // Nearly transparent overlay for macOS tap handling
                    )
                    .onTapGesture {
                        if node.nodeType == "note" {
                            // Open note editor for note nodes
                            logger.log("📝 Opening note editor for: \(node.title)", category: "TreeNodeView")
                            if let onOpenNoteEditor = onOpenNoteEditor {
                                onOpenNoteEditor(node)
                            } else {
                                showingNoteEditorForNode = node
                            }
                        } else if node.nodeType == "folder" {
                            // For folders, use unified click behavior
                            handleFolderClick()
                        } else {
                            // For other nodes, focus on this node (make it the new root)
                            // logger.log("🎯 Title clicked - focusing on node: \(node.id)", category: "TreeNodeView")
                            // Always route through the view model's focusOnNode method
                            if let onFocusNode = onFocusNode {
                                onFocusNode(node)
                            } else {
                                // This should not happen in practice as the callback is always provided
                                assertionFailure("onFocusNode callback not provided")
                            }

                            // SMART FOLDER RULE 3: Execute rule when focusing via title click
                            if node.nodeType == "smart_folder" {
                                logger.log("🧩 Smart folder focused via title click: \(node.title)", category: "TreeNodeView")
                                Task {
                                    await executeSmartFolderRule()
                                }
                            }
                        }
                    }
            }

            // Due date for tasks
            if let dueAt = node.taskData?.dueAt {
                Text(formatDueDate(dueAt))
                    .font(.system(size: fontSize - 3))
                    .foregroundColor(dueDateColor(dueAt))
                    .padding(.horizontal, 4)
            }

            // Tags (show first 2)
            if !node.tags.isEmpty {
                HStack(spacing: 2) {
                    ForEach(node.tags.prefix(2)) { tag in
                        Text(tag.name)
                            .font(.system(size: fontSize - 5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(tag.displayColor.opacity(0.2))
                            .foregroundColor(tag.displayColor)
                            .clipShape(Capsule())
                    }
                    if node.tags.count > 2 {
                        Text("+\(node.tags.count - 2)")
                            .font(.system(size: fontSize - 5))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Children count
            if hasChildren && !isExpanded {
                Text("\(node.childrenCount)")
                    .font(.system(size: fontSize - 4))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .draggable(node) {
            HStack {
                Image(systemName: nodeIcon)
                    .font(.system(size: fontSize))
                    .foregroundColor(nodeIconColor)
                Text(node.title)
                    .font(.system(size: fontSize))
            }
            .padding(8)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var chevronButton: some View {
        Button(action: {
            // logger.log("🔽 Chevron clicked for node: \(node.title) (type: \(node.nodeType))", category: "TreeNodeView")
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    // logger.log("📦 Collapsing node: \(node.title)", category: "TreeNodeView")
                    if let onCollapseNode = onCollapseNode {
                        onCollapseNode(node.id)
                    } else {
                        expandedNodes.remove(node.id)
                    }
                } else {
                    // logger.log("📤 Expanding node: \(node.title)", category: "TreeNodeView")
                    expandedNodes.insert(node.id)
                    // SMART FOLDER RULE 3: Execute rule when expanding via chevron
                    if node.nodeType == "smart_folder" {
                        // logger.log("🧩 Smart folder detected on expand, executing rule", category: "TreeNodeView")
                        Task {
                            await executeSmartFolderRule()
                        }
                    }
                }
            }
        }) {
            Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "circle")
                .font(.system(size: fontSize * 0.7))  // Chevron icon scales with font size
                .foregroundColor(hasChildren ? .primary : .clear)
        }
        #if os(macOS)
        .buttonStyle(BorderlessButtonStyle())
        #else
        .buttonStyle(PlainButtonStyle())
        #endif
        .frame(width: fontSize + 8, height: fontSize + 8)  // Button frame defines the clickable area
        .contentShape(Rectangle())
        .disabled(!hasChildren)
        .accessibilityLabel(hasChildren ? (isExpanded ? "Collapse" : "Expand") : "")
        .accessibilityHint(hasChildren ? "Double tap to \(isExpanded ? "collapse" : "expand") \(node.title)" : "")
        .accessibilityIdentifier("chevron_\(node.id)")
    }
    
    private func isNodeWithinBranch(_ nodeId: String, branchRoot: String) -> Bool {
        // Check if node is the branch root itself
        if nodeId == branchRoot {
            return true
        }

        // Check if node is in the children of the branch root (recursively)
        func isDescendant(of parentId: String, nodeToFind: String) -> Bool {
            let children = getChildren(parentId)
            for child in children {
                if child.id == nodeToFind {
                    return true
                }
                if isDescendant(of: child.id, nodeToFind: nodeToFind) {
                    return true
                }
            }
            return false
        }

        return isDescendant(of: branchRoot, nodeToFind: nodeId)
    }

    // MARK: - Node Click Handlers

    /// Handles click behavior for folder nodes: expand → focus → do nothing
    private func handleFolderClick() {
        if !isExpanded {
            // Step 1: If collapsed, expand it
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedNodes.insert(node.id)
            }
        } else if focusedNodeId != node.id {
            // Step 2: If expanded but not focused, focus on it
            if let onFocusNode = onFocusNode {
                onFocusNode(node)
            }
        }
        // Step 3: If already focused, do nothing
    }

    // MARK: - Smart Folder Execution

    /// Executes the smart folder rule by updating nodeChildren with results
    private func executeSmartFolderRule() async {
        logger.log("📞 executeSmartFolderRule called for: \(node.title)", category: "TreeNodeView")

        // Expand the folder to show results
        expandedNodes.insert(node.id)

        // Execute the smart folder
        if node.nodeType == "smart_folder", let onExecuteSmartFolder = onExecuteSmartFolder {
            await onExecuteSmartFolder(node)
        }
    }

    /// Instantiates a template by delegating to parent
    private func instantiateTemplate(_ template: Node) async {
        logger.log("📞 instantiateTemplate called for: \(template.title)", category: "TreeNodeView")

        if let onInstantiateTemplate = onInstantiateTemplate {
            await onInstantiateTemplate(template)
        } else {
            logger.log("⚠️ No onInstantiateTemplate handler provided", category: "TreeNodeView")
        }
    }
    
    // MARK: - Date Formatting

    /// Formats a due date string for display in the tree view.
    /// - Parameter dateString: ISO8601 date string
    /// - Returns: Formatted string (e.g., "Today", "Tomorrow", "3d")
    private func formatDueDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else {
                return ""
            }
            return formatDateHelper(date)
        }
        
        return formatDateHelper(date)
    }
    
    private func formatDateHelper(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            // Calculate the difference in calendar days, not time intervals
            // Start of today
            let startOfToday = calendar.startOfDay(for: now)
            // Start of the target date
            let startOfTargetDate = calendar.startOfDay(for: date)
            // Calculate days between the start of days
            let days = calendar.dateComponents([.day], from: startOfToday, to: startOfTargetDate).day ?? 0

            if days > 0 && days <= 7 {
                return "\(days)d"
            } else if days < 0 && days >= -7 {
                return "\(abs(days))d ago"
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                return dateFormatter.string(from: date)
            }
        }
    }
    
    /// Determines the appropriate color for a due date based on urgency.
    /// - Parameter dateString: ISO8601 date string
    /// - Returns: Color indicating urgency (red for overdue, orange for today, etc.)
    private func dueDateColor(_ dateString: String) -> Color {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else {
                return .secondary
            }
            return dueDateColorHelper(date)
        }
        
        return dueDateColorHelper(date)
    }
    
    private func handleDrop(draggedNode: Node, targetNode: Node, position: DropPosition) -> Bool {
        // Don't allow dropping on self
        guard draggedNode.id != targetNode.id else {
            logger.log("❌ Cannot drop on self", category: "TreeNodeView")
            return false
        }

        // Check if this is a parent change operation
        if position == .inside {
            // Validation: Don't allow dropping inside notes
            if targetNode.nodeType == "note" {
                logger.log("❌ Cannot drop inside a note", category: "TreeNodeView")
                return false
            }

            // Validation: Don't allow dropping inside smart folders
            if targetNode.nodeType == "smart_folder" {
                logger.log("❌ Cannot drop inside a smart folder", category: "TreeNodeView")
                return false
            }

            // Validation: Prevent circular references (don't drop a parent into its own child)
            if isNodeWithinBranch(targetNode.id, branchRoot: draggedNode.id) {
                logger.log("❌ Cannot drop a parent into its own child (circular reference)", category: "TreeNodeView")
                return false
            }

            // Valid parent change operation
            let message = "Moving '\(draggedNode.title)' inside '\(targetNode.title)'"
            logger.log("📦 Parent change: \(message)", category: "TreeNodeView")

            // Call the callback to perform the actual parent change
            Task {
                await onNodeDrop?(draggedNode, targetNode, position, message)
            }
            return true
        }

        // Check if we're dropping above/below a node (potentially changing parent)
        if position == .above || position == .below {
            // If dragged node has a different parent than target, this is a parent change
            if draggedNode.parentId != targetNode.parentId {
                // Parent change: moving to be a sibling of the target node
                // The new parent will be the target node's parent

                // First validate the new parent
                if let newParentId = targetNode.parentId {
                    // Check if the new parent is valid
                    // We need to get the parent node to validate
                    // For now, we'll pass this to the callback to handle
                    let message = "Moving '\(draggedNode.title)' to be sibling of '\(targetNode.title)'"
                    logger.log("📦 Parent change via sibling drop: \(message)", category: "TreeNodeView")

                    Task {
                        await onNodeDrop?(draggedNode, targetNode, position, message)
                    }
                    return true
                } else {
                    // Moving to root level
                    let message = "Moving '\(draggedNode.title)' to root level"
                    logger.log("📦 Moving to root: \(message)", category: "TreeNodeView")

                    Task {
                        await onNodeDrop?(draggedNode, targetNode, position, message)
                    }
                    return true
                }
            }
            // Same parent - this is regular sibling reordering
        }

        logger.log("🎯 Reordering \(draggedNode.title) to \(position == .above ? "before" : "after") \(targetNode.title)", category: "TreeNodeView")

        // Get all siblings
        let siblings: [Node]
        if let parentId = draggedNode.parentId {
            siblings = nodeChildren[parentId] ?? []
        } else {
            // Root nodes - use the getRootNodes callback if available
            if let getRootNodes = getRootNodes {
                siblings = getRootNodes()
            } else {
                // Fallback: can't reorder root nodes without getRootNodes callback
                logger.log("❌ Cannot reorder root nodes - getRootNodes callback not provided", category: "TreeNodeView")
                return false
            }
        }

        // Find positions
        let draggedIndex = siblings.firstIndex(where: { $0.id == draggedNode.id })
        let targetIndex = siblings.firstIndex(where: { $0.id == targetNode.id })

        guard let _ = draggedIndex, let targetIdx = targetIndex else {
            return false
        }

        // Calculate message
        let message: String
        if position == .above {
            if targetIdx == 0 {
                message = "You moved '\(draggedNode.title)' to the beginning"
            } else {
                let prevNode = siblings[targetIdx - 1]
                message = "You moved '\(draggedNode.title)' between '\(prevNode.title)' and '\(targetNode.title)'"
            }
        } else {
            // Below
            if targetIdx == siblings.count - 1 {
                message = "You moved '\(draggedNode.title)' to the end"
            } else {
                let nextNode = siblings[targetIdx + 1]
                message = "You moved '\(draggedNode.title)' between '\(targetNode.title)' and '\(nextNode.title)'"
            }
        }

        // Call the callback to perform the reorder and show alert
        Task {
            await onNodeDrop?(draggedNode, targetNode, position, message)
        }

        return true
    }

    private func dueDateColorHelper(_ date: Date) -> Color {
        let calendar = Calendar.current
        let now = Date()
        
        if date < now {
            return .red // Overdue
        } else if calendar.isDateInToday(date) {
            return .orange // Due today
        } else if calendar.isDateInTomorrow(date) {
            return .yellow // Due tomorrow
        } else {
            return .secondary // Future
        }
    }
}

// MARK: - Drop Delegate for Reordering

struct NodeDropDelegate: DropDelegate {
    let targetNode: Node
    let parentId: String?
    let dropPosition: Binding<DropPosition>
    let onDrop: (Node, Node, DropPosition) -> Bool
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let rowHeight: CGFloat

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [UTType.data]).first else {
            dropPosition.wrappedValue = .none
            return false
        }

        itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
            guard let data = data,
                  let draggedNode = try? JSONDecoder().decode(Node.self, from: data) else {
                DispatchQueue.main.async {
                    dropPosition.wrappedValue = .none
                }
                return
            }

            DispatchQueue.main.async {
                let position = getDropPosition(info: info)
                _ = onDrop(draggedNode, targetNode, position)
                // Reset drop position after handling the drop
                dropPosition.wrappedValue = .none
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        let position = getDropPosition(info: info)
        dropPosition.wrappedValue = position
    }

    func dropExited(info: DropInfo) {
        dropPosition.wrappedValue = .none
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let position = getDropPosition(info: info)
        dropPosition.wrappedValue = position
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Check if dragged item has same parent
        return true  // We'll validate properly in performDrop
    }

    private func getDropPosition(info: DropInfo) -> DropPosition {
        // y in the coordinate space of the drop target
        var y = info.location.y

        // Prefer measured height; fall back to an estimate
        let measuredHeight = rowHeight
        let estimatedHeight = fontSize + (2 * lineSpacing)
        let nodeHeight = max(measuredHeight, estimatedHeight)

        // Clamp y into [0, nodeHeight] to avoid overshoot
        y = min(max(0, y), nodeHeight)

        // Edge zones: true 10/80/10 but never thinner than 8pt
        let edgeZone = max(8, nodeHeight * 0.10)
        let topThreshold = edgeZone
        let bottomThreshold = nodeHeight - edgeZone

        let position: DropPosition
        if y <= topThreshold {
            position = .above
        } else if y >= bottomThreshold {
            position = .below
        } else {
            position = .inside
        }

        logger.log("📍 y=\(y), height=\(nodeHeight), edge=\(edgeZone), top=\(topThreshold), bottom=\(bottomThreshold), pos=\(position)", category: "TreeNodeView")
        return position
    }
}
