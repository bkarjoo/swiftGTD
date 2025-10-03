#if os(iOS)
import SwiftUI
import Core
import Models
import Services
import Networking

private let logger = Logger.shared

public struct TreeView_iOS: View {
    @StateObject private var viewModel = TreeViewModel()
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumb navigation
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
                
                // Main content
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(viewModel.focusedNode?.title ?? "All Nodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TreeToolbar(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingCreateDialog) {
                CreateNodeSheet(viewModel: viewModel)
                    .environmentObject(dataManager)
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
            } message: {
                Text("Delete \"\(viewModel.nodeToDelete?.title ?? "")\" and all its children?")
            }
            .task {
                // Set dataManager first, before loading nodes
                logger.log("📞 Setting dataManager on viewModel (in task)", category: "TreeView")
                viewModel.setDataManager(dataManager)
                logger.log("✅ DataManager set, now loading nodes", category: "TreeView")
                await viewModel.initialLoad()
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
}

// MARK: - Subviews

private struct BreadcrumbBar: View {
    let focusedNode: Node?
    let parentChain: [Node]
    let onNodeTap: (String) -> Void
    let onExitFocus: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: onExitFocus) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                        Text("All Nodes")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                if let node = focusedNode {
                    Text("/")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    
                    ForEach(parentChain, id: \.id) { parent in
                        Button(action: {
                            onNodeTap(parent.id)
                        }) {
                            Text(parent.title)
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
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
        }
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
                onShowDetails: viewModel.showDetails
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
                    onShowDetails: viewModel.showDetails
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
                Button(action: {
                    viewModel.createNodeType = "folder"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }) {
                    Label("Folder", systemImage: "folder")
                }
                
                Button(action: {
                    viewModel.createNodeType = "task"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }) {
                    Label("Task", systemImage: "checkmark.circle")
                }
                
                Button(action: {
                    viewModel.createNodeType = "note"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }) {
                    Label("Note", systemImage: "note.text")
                }
                
                Button(action: {
                    viewModel.createNodeType = "template"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }) {
                    Label("Template", systemImage: "doc.text")
                }
                
                Button(action: {
                    viewModel.createNodeType = "smart_folder"
                    viewModel.createNodeTitle = ""
                    viewModel.showingCreateDialog = true
                }) {
                    Label("Smart Folder", systemImage: "folder.badge.gearshape")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

private struct CreateNodeSheet: View {
    @ObservedObject var viewModel: TreeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isSubmitting = false

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
        NavigationView {
            Form {
                Section("New \(createNodeTypeTitle)") {
                    TextField("Title", text: $viewModel.createNodeTitle)
                        .textInputAutocapitalization(.sentences)
                        .onSubmit {
                            guard !isSubmitting, !viewModel.createNodeTitle.isEmpty else { return }
                            isSubmitting = true
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
                
                if let focusedNode = viewModel.focusedNode {
                    Section {
                        Label("Creating under: \(focusedNode.title)", systemImage: "folder")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Create \(createNodeTypeTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        guard !isSubmitting else { return }
                        isSubmitting = true
                        Task {
                            await viewModel.createNode(
                                type: viewModel.createNodeType,
                                title: viewModel.createNodeTitle,
                                parentId: viewModel.focusedNodeId
                            )
                            dismiss()
                        }
                    }
                    .disabled(viewModel.createNodeTitle.isEmpty || isSubmitting)
                }
            }
        }
    }
}
#endif
