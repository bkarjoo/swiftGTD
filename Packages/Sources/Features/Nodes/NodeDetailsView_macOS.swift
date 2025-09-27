#if os(macOS)
import SwiftUI
import Core
import Models
import Services

struct NodeDetailsView_macOS: View {
    let nodeId: String
    let treeViewModel: TreeViewModel?
    @StateObject private var viewModel = NodeDetailsViewModel()
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    private let logger = Logger.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                LoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) {
                    Task {
                        await viewModel.loadNode(nodeId: nodeId)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.node != nil {
                ScrollView {
                    VStack(spacing: 20) {
                        basicInformationSection
                        
                        // Type-specific sections
                        if viewModel.node?.nodeType == "task" {
                            taskDetailsSection
                        } else if viewModel.node?.nodeType == "note" {
                            noteDetailsSection
                        } else if viewModel.node?.nodeType == "template" {
                            templateDetailsSection
                        } else if viewModel.node?.nodeType == "smart_folder" {
                            smartFolderDetailsSection
                        } else if viewModel.node?.nodeType == "folder" {
                            folderDetailsSection
                        }
                        
                        metadataSection
                    }
                    .padding(20)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("Node not found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 700)
        .frame(minHeight: 400, idealHeight: 700, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            viewModel.setDataManager(dataManager)
            viewModel.setTreeViewModel(treeViewModel)
            await viewModel.loadNode(nodeId: nodeId)
        }
        .sheet(isPresented: $viewModel.showingParentPicker) {
            ParentPickerView(
                nodes: viewModel.availableParents,
                selectedNodeId: $viewModel.parentId,
                onSelect: { nodeId in
                    viewModel.updateField(\.parentId, value: nodeId)
                }
            )
        }
        .sheet(isPresented: $viewModel.showingTargetNodePicker) {
            TargetNodePickerView(
                nodes: viewModel.availableParents,
                selectedNodeId: $viewModel.templateTargetNodeId,
                onSelect: { nodeId in
                    viewModel.updateField(\.templateTargetNodeId, value: nodeId)
                }
            )
        }
        .sheet(isPresented: $viewModel.showingTagPicker) {
            if let node = viewModel.node {
                TagPickerView(node: node) {
                    // Only reload tags to preserve other unsaved changes
                    await viewModel.reloadTagsOnly(nodeId: node.id)
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Node Details")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button("Cancel") {
                logger.log("🔘 Cancel button clicked", category: "NodeDetailsView")
                if viewModel.hasChanges {
                    viewModel.cancel()
                }
                dismiss()
            }
            .buttonStyle(.plain)
            
            Button("Save") {
                logger.log("🔘 Save button clicked", category: "NodeDetailsView")
                Task {
                    await viewModel.save()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSaving)
            .keyboardShortcut(.return)
        }
        .padding()
    }
    
    private var basicInformationSection: some View {
        GroupBox("Basic Information") {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                HStack(alignment: .top) {
                    Text("Title")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("Title", text: $viewModel.title)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.title) { newValue in
                            viewModel.updateField(\.title, value: newValue)
                        }
                }
                
                // Parent
                HStack(alignment: .top) {
                    Text("Parent")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        logger.log("🔘 Parent picker button clicked", category: "NodeDetailsView")
                        Task {
                            await viewModel.loadAvailableParentsIfNeeded()
                            viewModel.showingParentPicker = true
                        }
                    }) {
                        HStack {
                            if let parentId = viewModel.parentId,
                               let parent = viewModel.availableParents.first(where: { $0.id == parentId }) {
                                Image(systemName: Icons.nodeIcon(for: parent.nodeType))
                                    .foregroundColor(Icons.nodeColor(for: parent.nodeType))
                                Text(parent.title)
                            } else {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                                Text("None (Root Level)")
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                // Sort Order
                HStack(alignment: .top) {
                    Text("Sort Order")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)

                    HStack {
                        Button(action: {
                            logger.log("🔘 Decrease sort order button clicked", category: "NodeDetailsView")
                            let newValue = viewModel.sortOrder - 10
                            viewModel.updateField(\.sortOrder, value: newValue)
                        }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)

                        TextField("", value: $viewModel.sortOrder, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .onChange(of: viewModel.sortOrder) { newValue in
                                viewModel.updateField(\.sortOrder, value: newValue)
                            }

                        Button(action: {
                            logger.log("🔘 Increase sort order button clicked", category: "NodeDetailsView")
                            let newValue = viewModel.sortOrder + 10
                            viewModel.updateField(\.sortOrder, value: newValue)
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }

                // Tags
                HStack(alignment: .top) {
                    Text("Tags")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)

                    HStack {
                        if viewModel.tags.isEmpty {
                            Text("No tags")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            HStack(spacing: 6) {
                                ForEach(viewModel.tags) { tag in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(hex: tag.color ?? "#808080"))
                                            .frame(width: 8, height: 8)
                                        Text(tag.name)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: tag.color ?? "#808080").opacity(0.2))
                                    .cornerRadius(10)
                                }
                            }
                        }

                        Button(action: {
                            logger.log("🏷️ Opening tag picker for node", category: "NodeDetailsView")
                            viewModel.showingTagPicker = true
                        }) {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }
            .padding(.vertical, 5)
        }
    }
    
    private var folderDetailsSection: some View {
        GroupBox("Folder Details") {
            VStack(alignment: .leading, spacing: 12) {
                // Description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.folderDescription)
                        .frame(minHeight: 60)
                        .font(.system(.body, design: .default))
                        .onChange(of: viewModel.folderDescription) { newValue in
                            viewModel.updateField(\.folderDescription, value: newValue)
                        }
                }
            }
        }
    }

    private var smartFolderDetailsSection: some View {
        GroupBox("Smart Folder Settings") {
            VStack(alignment: .leading, spacing: 12) {
                // Description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.smartFolderDescription)
                        .frame(minHeight: 60)
                        .font(.system(.body, design: .default))
                        .onChange(of: viewModel.smartFolderDescription) { newValue in
                            viewModel.updateField(\.smartFolderDescription, value: newValue)
                        }
                }
                
                // Auto Refresh toggle
                Toggle("Auto Refresh", isOn: $viewModel.smartFolderAutoRefresh)
                    .onChange(of: viewModel.smartFolderAutoRefresh) { newValue in
                        viewModel.updateField(\.smartFolderAutoRefresh, value: newValue)
                    }
                
                // Rule Selection
                HStack {
                    Text("Rule:")
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.smartFolderRuleId) {
                        Text("No rule selected")
                            .tag(nil as String?)
                        
                        ForEach(viewModel.availableRules) { rule in
                            HStack {
                                if rule.isSystem {
                                    Image(systemName: "lock.shield")
                                        .foregroundColor(.orange)
                                } else if rule.isPublic {
                                    Image(systemName: "globe")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "person")
                                        .foregroundColor(.gray)
                                }
                                VStack(alignment: .leading) {
                                    Text(rule.name)
                                    if let description = rule.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .tag(rule.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: viewModel.smartFolderRuleId) { newValue in
                        viewModel.updateField(\.smartFolderRuleId, value: newValue)
                    }
                    Spacer()
                }
            }
            .padding()
        }
    }
    
    private var templateDetailsSection: some View {
        GroupBox("Template Settings") {
            VStack(alignment: .leading, spacing: 12) {
                // Description
                HStack(alignment: .top) {
                    Text("Description")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.templateDescription)
                        .font(.system(size: 13))
                        .frame(minHeight: 80, maxHeight: 150)
                        .border(Color.gray.opacity(0.2))
                        .onChange(of: viewModel.templateDescription) { newValue in
                            viewModel.updateField(\.templateDescription, value: newValue)
                        }
                }
                
                // Category
                HStack(alignment: .top) {
                    Text("Category")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("Category", text: $viewModel.templateCategory)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.templateCategory) { newValue in
                            viewModel.updateField(\.templateCategory, value: newValue)
                        }
                }
                
                // Usage Count (read-only)
                HStack(alignment: .top) {
                    Text("Usage Count")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Text("\(viewModel.templateUsageCount)")
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                // Target Node
                HStack(alignment: .top) {
                    Text("Target Node")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        logger.log("🔘 Target node picker button clicked", category: "NodeDetailsView")
                        viewModel.showingTargetNodePicker = true
                    }) {
                        HStack {
                            if let targetId = viewModel.templateTargetNodeId,
                               let target = viewModel.availableParents.first(where: { $0.id == targetId }) {
                                Image(systemName: Icons.nodeIcon(for: target.nodeType))
                                    .foregroundColor(Icons.nodeColor(for: target.nodeType))
                                Text(target.title)
                            } else {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                                Text("None")
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                // Create Container
                HStack(alignment: .top) {
                    Text("Create Container")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Toggle("Create a container folder when using this template", isOn: $viewModel.templateCreateContainer)
                        .toggleStyle(CheckboxToggleStyle())
                        .onChange(of: viewModel.templateCreateContainer) { newValue in
                            viewModel.updateField(\.templateCreateContainer, value: newValue)
                        }
                    Spacer()
                }
            }
            .padding(.vertical, 5)
        }
    }
    
    private var noteDetailsSection: some View {
        GroupBox("Note Content") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("Body")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $viewModel.noteBody)
                        .font(.system(size: 13))
                        .frame(minHeight: 250, maxHeight: 400)
                        .border(Color.gray.opacity(0.2))
                        .onChange(of: viewModel.noteBody) { newValue in
                            viewModel.updateField(\.noteBody, value: newValue)
                        }
                }
            }
            .padding(.vertical, 5)
        }
    }
    
    private var taskDetailsSection: some View {
        GroupBox("Task Details") {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack(alignment: .top) {
                    Text("Status")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.taskStatus) {
                        Text("To Do").tag("todo")
                        Text("In Progress").tag("in_progress")
                        Text("Done").tag("done")
                        Text("Dropped").tag("dropped")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: 300)
                    .onChange(of: viewModel.taskStatus) { newValue in
                        viewModel.updateField(\.taskStatus, value: newValue)
                    }
                    Spacer()
                }
                
                // Priority
                HStack(alignment: .top) {
                    Text("Priority")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.taskPriority) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: 300)
                    .onChange(of: viewModel.taskPriority) { newValue in
                        viewModel.updateField(\.taskPriority, value: newValue)
                    }
                    Spacer()
                }
                
                // Description
                HStack(alignment: .top) {
                    Text("Description")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.taskDescription)
                        .font(.system(size: 13))
                        .frame(minHeight: 80, maxHeight: 200)
                        .border(Color.gray.opacity(0.2))
                        .onChange(of: viewModel.taskDescription) { newValue in
                            viewModel.updateField(\.taskDescription, value: newValue)
                        }
                }
                
                // Due Date
                HStack(alignment: .top) {
                    Text("Due Date")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    Toggle("", isOn: Binding(
                        get: { viewModel.taskDueDate != nil },
                        set: { enabled in
                            if enabled {
                                viewModel.taskDueDate = Date()
                            } else {
                                viewModel.taskDueDate = nil
                            }
                            viewModel.checkForChanges()
                        }
                    ))
                    .toggleStyle(CheckboxToggleStyle())
                    
                    if viewModel.taskDueDate != nil {
                        DatePicker("", selection: Binding(
                            get: { viewModel.taskDueDate ?? Date() },
                            set: { 
                                viewModel.taskDueDate = $0
                                viewModel.checkForChanges()
                            }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    
                    Spacer()
                }
                
                // Earliest Start Date
                HStack(alignment: .top) {
                    Text("Earliest Start")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    
                    Toggle("", isOn: Binding(
                        get: { viewModel.taskEarliestStartDate != nil },
                        set: { enabled in
                            if enabled {
                                viewModel.taskEarliestStartDate = Date()
                            } else {
                                viewModel.taskEarliestStartDate = nil
                            }
                            viewModel.checkForChanges()
                        }
                    ))
                    .toggleStyle(CheckboxToggleStyle())
                    
                    if viewModel.taskEarliestStartDate != nil {
                        DatePicker("", selection: Binding(
                            get: { viewModel.taskEarliestStartDate ?? Date() },
                            set: { 
                                viewModel.taskEarliestStartDate = $0
                                viewModel.checkForChanges()
                            }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    
                    Spacer()
                }
                
                // Archived
                HStack(alignment: .top) {
                    Text("Archived")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    Toggle("Archive this task", isOn: $viewModel.taskArchived)
                        .toggleStyle(CheckboxToggleStyle())
                        .onChange(of: viewModel.taskArchived) { newValue in
                            viewModel.updateField(\.taskArchived, value: newValue)
                        }
                    Spacer()
                }
            }
            .padding(.vertical, 5)
        }
    }
    
    private var metadataSection: some View {
        GroupBox("Information") {
            VStack(alignment: .leading, spacing: 12) {
                if let node = viewModel.node {
                    // Node Type
                    HStack(alignment: .top) {
                        Text("Type")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Label(
                            NodeType(rawValue: node.nodeType)?.displayName ?? node.nodeType,
                            systemImage: Icons.nodeIcon(for: node.nodeType)
                        )
                        .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    // Created At
                    HStack(alignment: .top) {
                        Text("Created")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text(formatDate(node.createdAt))
                        Spacer()
                    }
                    
                    // Updated At
                    HStack(alignment: .top) {
                        Text("Updated")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Text(formatDate(node.updatedAt))
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        
        return displayFormatter.string(from: date)
    }
}

// MARK: - Parent Picker View

private struct ParentPickerView: View {
    private let logger = Logger.shared
    let nodes: [Node]
    @Binding var selectedNodeId: String?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    private var filteredNodes: [Node] {
        if searchText.isEmpty {
            return nodes
        }
        return nodes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Parent")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    logger.log("🔘 Picker cancel button clicked", category: "NodeDetailsView")
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search nodes", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding()
            
            // List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // None option
                    Button(action: {
                        logger.log("🔘 Picker 'None' selected", category: "NodeDetailsView")
                        onSelect(nil)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.secondary)
                            Text("None (Root Level)")
                            Spacer()
                            if selectedNodeId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedNodeId == nil ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    // Node options
                    ForEach(filteredNodes) { node in
                        Button(action: {
                            logger.log("🔘 Picker node selected: \(node.id)", category: "NodeDetailsView")
                            onSelect(node.id)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: Icons.nodeIcon(for: node.nodeType))
                                    .foregroundColor(Icons.nodeColor(for: node.nodeType))
                                Text(node.title)
                                Spacer()
                                if selectedNodeId == node.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedNodeId == node.id ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Target Node Picker View

private struct TargetNodePickerView: View {
    private let logger = Logger.shared
    let nodes: [Node]
    @Binding var selectedNodeId: String?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    private var filteredNodes: [Node] {
        if searchText.isEmpty {
            return nodes
        }
        return nodes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Target Node")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    logger.log("🔘 Picker cancel button clicked", category: "NodeDetailsView")
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search nodes", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding()
            
            // List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // None option
                    Button(action: {
                        logger.log("🔘 Picker 'None' selected", category: "NodeDetailsView")
                        onSelect(nil)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.secondary)
                            Text("None")
                            Spacer()
                            if selectedNodeId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedNodeId == nil ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    // Node options
                    ForEach(filteredNodes) { node in
                        Button(action: {
                            logger.log("🔘 Picker node selected: \(node.id)", category: "NodeDetailsView")
                            onSelect(node.id)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: Icons.nodeIcon(for: node.nodeType))
                                    .foregroundColor(Icons.nodeColor(for: node.nodeType))
                                Text(node.title)
                                Spacer()
                                if selectedNodeId == node.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedNodeId == node.id ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Helper Views

private struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Error")
                .font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
#endif