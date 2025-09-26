import SwiftUI
import Core
import Models
import Services

public struct NodeDetailView: View {
    let node: Node
    let treeViewModel: TreeViewModel?

    public init(node: Node, treeViewModel: TreeViewModel? = nil) {
        self.node = node
        self.treeViewModel = treeViewModel
    }
    @EnvironmentObject var dataManager: DataManager
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedContent: String = ""
    @State private var showingDeleteAlert = false
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                contentSection
                metadataSection
                Spacer()
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: {
                        if isEditing {
                            saveChanges()
                        } else {
                            startEditing()
                        }
                    }) {
                        Label(isEditing ? "Save" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                    }
                    
                    Button(role: .destructive, action: {
                        showingDeleteAlert = true
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Node", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteNode()
            }
        } message: {
            Text("Are you sure you want to delete this \(NodeType(rawValue: node.nodeType)?.displayName.lowercased() ?? "node")?")
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        HStack {
            Image(systemName: NodeType(rawValue: node.nodeType)?.systemImage ?? "doc")
                .font(.title)
                .foregroundColor(.blue)
            
            if isEditing {
                TextField("Title", text: $editedTitle)
                    .font(.title2)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                Text(node.title)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            if node.nodeType == "task" {
                taskCompletionButton
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var taskCompletionButton: some View {
        Button(action: {
            Task {
                // Route through TreeViewModel if available to ensure smart folder results are updated
                if let treeViewModel = treeViewModel {
                    await treeViewModel.toggleTaskStatus(node)
                } else {
                    // Fallback to direct DataManager call (won't update smart folder results)
                    await dataManager.toggleNodeCompletion(node)
                }
            }
        }) {
            Image(systemName: node.taskData?.completedAt != nil ? "checkmark.circle.fill" : "circle")
                .font(.title)
                .foregroundColor(node.taskData?.completedAt != nil ? .green : .gray)
        }
    }
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.headline)
            
            if isEditing {
                TextEditor(text: $editedContent)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            } else {
                descriptionText
            }
        }
        .padding(.horizontal)
    }
    
    private var descriptionText: some View {
        Text(node.taskData?.description ?? node.noteData?.body ?? "No description")
            .foregroundColor((node.taskData?.description ?? node.noteData?.body) == nil ? .secondary : .primary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let dueDate = node.taskData?.dueAt {
                HStack {
                    Text("Due Date:")
                        .fontWeight(.semibold)
                    Text(dueDate)
                }
            }
            
            if !node.tags.isEmpty {
                tagsSection
            }
            
            HStack {
                Text("Created:")
                    .fontWeight(.semibold)
                Text(node.createdAt)
            }
            
            if let completedAt = node.taskData?.completedAt {
                HStack {
                    Text("Completed:")
                        .fontWeight(.semibold)
                    Text(completedAt)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags:")
                .fontWeight(.semibold)
            
            FlowLayout(spacing: 8) {
                ForEach(node.tags) { tag in
                    TagChip(tag: tag)
                }
            }
        }
    }
    
    // MARK: - Functions
    
    func startEditing() {
        editedTitle = node.title
        editedContent = node.taskData?.description ?? node.noteData?.body ?? ""
        isEditing = true
    }
    
    func saveChanges() {
        // TODO: Create proper update logic with new Node structure
        // For now, just disable editing
        isEditing = false
    }
    
    func deleteNode() {
        let manager = dataManager
        Task {
            await manager.deleteNode(node)
        }
    }
}

// FlowLayout is now imported from Core module

// Preview commented out - needs update for new Node structure
// #Preview {
//     NavigationView {
//         NodeDetailView(node: Node(...))
//         .environmentObject(DataManager())
//     }
// }
