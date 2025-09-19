import SwiftUI
import Core
import Models
import Services
import Networking

private let logger = Logger.shared

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
    let onDelete: (Node) -> Void
    let onToggleTaskStatus: (Node) -> Void
    let onRefresh: () async -> Void
    let onUpdateNodeTitle: (String, String) async -> Void
    let onUpdateSingleNode: (String) async -> Void

    @State private var showingDetailsForNode: Node?
    @State private var showingTagPickerForNode: Node?
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
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
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Create the main row content
            nodeRowContent
                .id(node.id)  // Add ID for ScrollViewReader to find this node
                .contentShape(Rectangle()) // Make entire row tappable
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
                            showingDetailsForNode = node
                        }
                    }) {
                        Label(node.nodeType == "smart_folder" ? "Execute" : "Details",
                              systemImage: node.nodeType == "smart_folder" ? "play.circle" : "info.circle")
                    }
                    
                    // Note nodes don't have focus mode
                    if node.nodeType != "note" {
                        Button(action: {
                            logger.log("🔘 Focus button clicked for node: \(node.id)", category: "TreeNodeView")
                            // Focus on this node
                            focusedNodeId = node.id
                            expandedNodes.insert(node.id)
                            NotificationCenter.default.post(name: .focusChanged, object: nil)
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
                            showingTagPickerForNode = node
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
                        logger.log("🔘 Delete button clicked for node: \(node.id)", category: "TreeNodeView")
                        onDelete(node)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
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
                        onDelete: onDelete,
                        onToggleTaskStatus: onToggleTaskStatus,
                        onRefresh: onRefresh,
                        onUpdateNodeTitle: onUpdateNodeTitle,
                        onUpdateSingleNode: onUpdateSingleNode
                    )
                }
            }
        }
        .sheet(item: $showingDetailsForNode) { node in
            NodeDetailsView(nodeId: node.id, treeViewModel: nil)
        }
        .sheet(item: $showingTagPickerForNode) { node in
            TagPickerView(node: node) {
                // Just update the single node to show updated tags
                await onUpdateSingleNode(node.id)
            }
        }
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
            
            // Expand/collapse chevron
            Button(action: {
                logger.log("🔽 Chevron clicked for node: \(node.title) (type: \(node.nodeType))", category: "TreeNodeView")
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        logger.log("📦 Collapsing node: \(node.title)", category: "TreeNodeView")
                        expandedNodes.remove(node.id)
                    } else {
                        logger.log("📤 Expanding node: \(node.title)", category: "TreeNodeView")
                        expandedNodes.insert(node.id)
                        // SMART FOLDER RULE 3: Execute rule when expanding via chevron
                        if node.nodeType == "smart_folder" {
                            logger.log("🧩 Smart folder detected on expand, executing rule", category: "TreeNodeView")
                            Task {
                                await executeSmartFolderRule()
                            }
                        }
                    }
                }
            }) {
                Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "circle")
                    .font(.system(size: 10))
                    .frame(width: 16, height: 16)
                    .foregroundColor(hasChildren ? .primary : .clear)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!hasChildren)
            
            // Node icon - clickable to toggle expand/collapse (same as chevron)
            // For tasks, also toggles completion status
            Button(action: {
                if node.nodeType == "task" {
                    // For tasks, toggle completion status
                    logger.log("🔘 Task checkbox clicked for node: \(node.id) - \(node.title)", category: "TreeNodeView")
                    logger.log("Current completion status: \(node.taskData?.completedAt != nil)", category: "TreeNodeView")
                    onToggleTaskStatus(node)
                    logger.log("✅ onToggleTaskStatus called", category: "TreeNodeView")
                } else if hasChildren {
                    // For non-task nodes with children, toggle expand/collapse (same as chevron)
                    logger.log("🔽 Icon clicked for node: \(node.title) (type: \(node.nodeType))", category: "TreeNodeView")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            logger.log("📦 Collapsing node via icon: \(node.title)", category: "TreeNodeView")
                            expandedNodes.remove(node.id)
                        } else {
                            logger.log("📤 Expanding node via icon: \(node.title)", category: "TreeNodeView")
                            expandedNodes.insert(node.id)
                            // SMART FOLDER RULE 3: Execute rule when expanding via icon
                            if node.nodeType == "smart_folder" {
                                logger.log("🧩 Smart folder detected on expand via icon, executing rule", category: "TreeNodeView")
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
                            showingNoteEditorForNode = node
                        } else {
                            // Focus on this node (make it the new root)
                            logger.log("🎯 Title clicked - focusing on node: \(node.id)", category: "TreeNodeView")
                            focusedNodeId = node.id
                            // Auto-expand when focusing
                            expandedNodes.insert(node.id)

                            // If selected node is not within this focused branch, move selection to focused node
                            if let currentSelected = selectedNodeId {
                                if !isNodeWithinBranch(currentSelected, branchRoot: node.id) {
                                    logger.log("🎯 Moving selection to focused node as current selection is outside branch", category: "TreeNodeView")
                                    selectedNodeId = node.id
                                }
                            } else {
                                // No selection, select the focused node
                                selectedNodeId = node.id
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
        .padding(.horizontal, 8)
        .padding(.vertical, lineSpacing)
        .background(selectedNodeId == node.id ? Color.gray.opacity(0.1) : Color.clear)
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

    // MARK: - Smart Folder Execution

    /// Executes the smart folder's rule by calling the API to get its contents.
    /// Updates nodeChildren with the results and expands the smart folder to display them.
    private func executeSmartFolderRule() async {
        // Log execution start with details
        logger.log("📞 Executing smart folder rule for: \(node.title)", category: "TreeNodeView")
        logger.log("   Smart folder ID: \(node.id)", category: "TreeNodeView")
        logger.log("   Node type: \(node.nodeType)", category: "TreeNodeView")

        // Log smart folder metadata if available
        if let smartFolderData = node.smartFolderData {
            logger.log("   Rule ID: \(smartFolderData.ruleId ?? "nil")", category: "TreeNodeView")
            logger.log("   Auto-refresh: \(smartFolderData.autoRefresh ?? true)", category: "TreeNodeView")
        }

        do {
            // Execute the smart folder rule via API
            logger.log("🌐 Making API call to execute smart folder...", category: "TreeNodeView")
            let api = APIClient.shared
            let resultNodes = try await api.executeSmartFolderRule(smartFolderId: node.id)

            logger.log("✅ Smart folder executed successfully, returned \(resultNodes.count) nodes", category: "TreeNodeView")

            // Log sample results for debugging
            for (index, node) in resultNodes.prefix(3).enumerated() {
                logger.log("   Result \(index + 1): \(node.title) (type: \(node.nodeType), id: \(node.id))", category: "TreeNodeView")
            }
            if resultNodes.count > 3 {
                logger.log("   ... and \(resultNodes.count - 3) more nodes", category: "TreeNodeView")
            }

            // Update UI with smart folder contents
            logger.log("📝 Updating nodeChildren for smart folder", category: "TreeNodeView")
            await MainActor.run {
                nodeChildren[node.id] = resultNodes
                // Expand the smart folder to show results
                expandedNodes.insert(node.id)
                logger.log("✅ UI updated with smart folder results", category: "TreeNodeView")
            }

            logger.log("✅ Smart folder execution complete", category: "TreeNodeView")
        } catch {
            logger.log("❌ Failed to execute smart folder rule: \(error)", level: .error, category: "TreeNodeView")
            logger.log("   Error type: \(type(of: error))", level: .error, category: "TreeNodeView")
            logger.log("   Error description: \(error.localizedDescription)", level: .error, category: "TreeNodeView")
        }
    }

    // MARK: - Template Operations

    /// Instantiates a template node, creating a new instance with all its contents.
    /// - Parameter template: The template node to instantiate
    private func instantiateTemplate(_ template: Node) async {
        logger.log("📞 Instantiating template: \(template.title)", category: "TreeNodeView")
        
        do {
            // Generate a name for the instantiated copy
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let dateString = dateFormatter.string(from: Date())
            let name = "\(template.title) - \(dateString)"
            
            // Call the API to instantiate the template
            // parentId will be nil, so it uses the template's target_node_id
            let api = APIClient.shared
            let newNode = try await api.instantiateTemplate(
                templateId: template.id,
                name: name,
                parentId: nil
            )
            
            logger.log("✅ Template instantiated successfully: \(newNode.title)", category: "TreeNodeView")
            
            // Trigger a refresh by calling the parent view's refresh callback
            await onRefresh()
        } catch {
            logger.log("❌ Failed to instantiate template: \(error)", level: .error, category: "TreeNodeView")
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
            let days = calendar.dateComponents([.day], from: now, to: date).day ?? 0
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
