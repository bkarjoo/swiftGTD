#if os(iOS)
import SwiftUI
import Core
import Models
import Services

struct NodeDetailsView_iOS: View {
    let nodeId: String
    let treeViewModel: TreeViewModel?
    @StateObject private var viewModel = NodeDetailsViewModel()
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    private let logger = Logger.shared
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    LoadingView()
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error) {
                        Task {
                            await viewModel.loadNode(nodeId: nodeId)
                        }
                    }
                } else if let node = viewModel.node {
                    Form {
                        basicInformationSection
                        
                        // Type-specific sections
                        if node.nodeType == "task" {
                            taskDetailsSection
                        } else if node.nodeType == "note" {
                            noteDetailsSection
                        } else if node.nodeType == "template" {
                            templateDetailsSection
                        } else if node.nodeType == "smart_folder" {
                            smartFolderDetailsSection
                        }
                        
                        metadataSection
                    }
                } else {
                    Text("Node not found")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Node Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        logger.log("🔘 Cancel button tapped", category: "NodeDetailsView")
                        if viewModel.hasChanges {
                            viewModel.cancel()
                        }
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        logger.log("🔘 Save button tapped", category: "NodeDetailsView")
                        Task {
                            await viewModel.save()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
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
        .sheet(isPresented: $viewModel.showingRulePicker) {
            RulePickerView(
                rules: viewModel.availableRules,
                selectedRuleId: $viewModel.smartFolderRuleId,
                onSelect: { ruleId in
                    viewModel.updateField(\.smartFolderRuleId, value: ruleId)
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
    
    private var basicInformationSection: some View {
        Section("Basic Information") {
            // Title
            HStack {
                Text("Title")
                    .foregroundColor(.secondary)
                TextField("Title", text: $viewModel.title)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: viewModel.title) { newValue in
                        viewModel.updateField(\.title, value: newValue)
                    }
            }
            
            // Parent
            Button(action: {
                logger.log("🔘 Parent picker button tapped", category: "NodeDetailsView")
                viewModel.showingParentPicker = true
            }) {
                HStack {
                    Text("Parent")
                        .foregroundColor(.primary)
                    Spacer()
                    if let parentId = viewModel.parentId,
                       let parent = viewModel.availableParents.first(where: { $0.id == parentId }) {
                        Text(parent.title)
                            .foregroundColor(.secondary)
                    } else {
                        Text("None")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sort Order
            HStack {
                Text("Sort Order")
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    let newValue = viewModel.sortOrder - 10
                    viewModel.updateField(\.sortOrder, value: newValue)
                }) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)

                Text("\(viewModel.sortOrder)")
                    .frame(minWidth: 50)
                    .multilineTextAlignment(.center)

                Button(action: {
                    let newValue = viewModel.sortOrder + 10
                    viewModel.updateField(\.sortOrder, value: newValue)
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            // Tags
            Button(action: {
                logger.log("🏷️ Opening tag picker for node", category: "NodeDetailsView")
                viewModel.showingTagPicker = true
            }) {
                HStack {
                    Text("Tags")
                        .foregroundColor(.primary)
                    Spacer()
                    if viewModel.tags.isEmpty {
                        Text("No tags")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        HStack(spacing: 4) {
                            ForEach(viewModel.tags.prefix(3)) { tag in
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color(hex: tag.color ?? "#808080"))
                                        .frame(width: 6, height: 6)
                                    Text(tag.name)
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: tag.color ?? "#808080").opacity(0.2))
                                .cornerRadius(8)
                            }
                            if viewModel.tags.count > 3 {
                                Text("+\(viewModel.tags.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var smartFolderDetailsSection: some View {
        Section("Smart Folder Settings") {
            // Description
            VStack(alignment: .leading) {
                Text("Description")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                TextEditor(text: $viewModel.smartFolderDescription)
                    .frame(minHeight: 80)
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
            Button(action: {
                logger.log("🔘 Rule picker button tapped", category: "NodeDetailsView")
                viewModel.showingRulePicker = true
            }) {
                HStack {
                    Text("Rule")
                        .foregroundColor(.primary)
                    Spacer()
                    if let ruleId = viewModel.smartFolderRuleId,
                       let rule = viewModel.availableRules.first(where: { $0.id == ruleId }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(rule.name)
                                .foregroundColor(.secondary)
                            if let description = rule.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("No rule selected")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var templateDetailsSection: some View {
        Section("Template Settings") {
            // Description
            VStack(alignment: .leading) {
                Text("Description")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                TextEditor(text: $viewModel.templateDescription)
                    .frame(minHeight: 80)
                    .onChange(of: viewModel.templateDescription) { newValue in
                        viewModel.updateField(\.templateDescription, value: newValue)
                    }
            }
            
            // Category
            HStack {
                Text("Category")
                    .foregroundColor(.secondary)
                TextField("Category", text: $viewModel.templateCategory)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: viewModel.templateCategory) { newValue in
                        viewModel.updateField(\.templateCategory, value: newValue)
                    }
            }
            
            // Usage Count (read-only)
            HStack {
                Text("Usage Count")
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.templateUsageCount)")
                    .foregroundColor(.secondary)
            }
            
            // Target Node
            Button(action: {
                viewModel.showingTargetNodePicker = true
            }) {
                HStack {
                    Text("Target Node")
                        .foregroundColor(.primary)
                    Spacer()
                    if let targetId = viewModel.templateTargetNodeId,
                       let target = viewModel.availableParents.first(where: { $0.id == targetId }) {
                        Text(target.title)
                            .foregroundColor(.secondary)
                    } else {
                        Text("None")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Create Container toggle
            Toggle("Create Container", isOn: $viewModel.templateCreateContainer)
                .onChange(of: viewModel.templateCreateContainer) { newValue in
                    viewModel.updateField(\.templateCreateContainer, value: newValue)
                }
        }
    }
    
    private var noteDetailsSection: some View {
        Section("Note Content") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Body")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                TextEditor(text: $viewModel.noteBody)
                    .frame(minHeight: 200)
                    .font(.system(.body, design: .default))
                    .onChange(of: viewModel.noteBody) { newValue in
                        viewModel.updateField(\.noteBody, value: newValue)
                    }
            }
        }
    }
    
    private var taskDetailsSection: some View {
        Section("Task Details") {
            // Status
            Picker("Status", selection: $viewModel.taskStatus) {
                Text("To Do").tag("todo")
                Text("In Progress").tag("in_progress")
                Text("Done").tag("done")
                Text("Dropped").tag("dropped")
            }
            .onChange(of: viewModel.taskStatus) { newValue in
                viewModel.updateField(\.taskStatus, value: newValue)
            }
            
            // Priority
            Picker("Priority", selection: $viewModel.taskPriority) {
                Text("Low").tag("low")
                Text("Medium").tag("medium")
                Text("High").tag("high")
                Text("Urgent").tag("urgent")
            }
            .onChange(of: viewModel.taskPriority) { newValue in
                viewModel.updateField(\.taskPriority, value: newValue)
            }
            
            // Description
            VStack(alignment: .leading) {
                Text("Description")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                TextEditor(text: $viewModel.taskDescription)
                    .frame(minHeight: 80)
                    .onChange(of: viewModel.taskDescription) { newValue in
                        viewModel.updateField(\.taskDescription, value: newValue)
                    }
            }
            
            // Due Date
            Toggle("Due Date", isOn: Binding(
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
            
            if viewModel.taskDueDate != nil {
                DatePicker("Due", selection: Binding(
                    get: { viewModel.taskDueDate ?? Date() },
                    set: { 
                        viewModel.taskDueDate = $0
                        viewModel.checkForChanges()
                    }
                ), displayedComponents: [.date, .hourAndMinute])
            }
            
            // Earliest Start Date
            Toggle("Earliest Start", isOn: Binding(
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
            
            if viewModel.taskEarliestStartDate != nil {
                DatePicker("Start", selection: Binding(
                    get: { viewModel.taskEarliestStartDate ?? Date() },
                    set: { 
                        viewModel.taskEarliestStartDate = $0
                        viewModel.checkForChanges()
                    }
                ), displayedComponents: [.date, .hourAndMinute])
            }
            
            // Archived
            Toggle("Archived", isOn: $viewModel.taskArchived)
                .onChange(of: viewModel.taskArchived) { newValue in
                    viewModel.updateField(\.taskArchived, value: newValue)
                }
        }
    }
    
    private var metadataSection: some View {
        Section("Information") {
            if let node = viewModel.node {
                // Node Type
                HStack {
                    Text("Type")
                        .foregroundColor(.secondary)
                    Spacer()
                    Label(
                        NodeType(rawValue: node.nodeType)?.displayName ?? node.nodeType,
                        systemImage: Icons.nodeIcon(for: node.nodeType)
                    )
                    .foregroundColor(.primary)
                }
                
                // Created At
                HStack {
                    Text("Created")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(node.createdAt))
                        .foregroundColor(.secondary)
                }
                
                // Updated At
                HStack {
                    Text("Updated")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(node.updatedAt))
                        .foregroundColor(.secondary)
                }
            }
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
        NavigationStack {
            List {
                // None option
                Button(action: {
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
                }
                .foregroundColor(.primary)
                
                // Node options
                ForEach(filteredNodes) { node in
                    Button(action: {
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
                    }
                    .foregroundColor(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search nodes")
            .navigationTitle("Select Parent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Target Node Picker View

private struct TargetNodePickerView: View {
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
        NavigationStack {
            List {
                // None option
                Button(action: {
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
                }
                .foregroundColor(.primary)
                
                // Node options
                ForEach(filteredNodes) { node in
                    Button(action: {
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
                    }
                    .foregroundColor(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search nodes")
            .navigationTitle("Select Target Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Rule Picker View

private struct RulePickerView: View {
    let rules: [Rule]
    @Binding var selectedRuleId: String?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    private var filteredRules: [Rule] {
        if searchText.isEmpty {
            return rules
        }
        return rules.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // None option
                Button(action: {
                    onSelect(nil)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text("None")
                            Text("No rule selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedRuleId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .foregroundColor(.primary)
                
                // Rule options
                ForEach(filteredRules) { rule in
                    Button(action: {
                        onSelect(rule.id)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: rule.isSystem ? "lock.shield" : (rule.isPublic ? "globe" : "person"))
                                .foregroundColor(rule.isSystem ? .orange : (rule.isPublic ? .blue : .gray))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                if let description = rule.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if selectedRuleId == rule.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search rules")
            .navigationTitle("Select Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
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