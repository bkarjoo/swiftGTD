import SwiftUI
import Models
import Networking
import Core

private let logger = Logger.shared

public struct TagPickerView: View {
    let node: Node
    let onDismiss: () async -> Void
    
    @State private var searchText = ""
    @State private var availableTags: [Tag] = []
    @State private var filteredTags: [Tag] = []
    @State private var nodeTags: [Tag] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    
    // Debounce timer for search
    @State private var searchTask: Task<Void, Never>?
    
    public init(node: Node, onDismiss: @escaping () async -> Void) {
        self.node = node
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        #if os(iOS)
        NavigationView {
            content
                .navigationTitle("Manage Tags")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            Task {
                                await onDismiss()
                                dismiss()
                            }
                        }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Tags")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    Task {
                        await onDismiss()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            content
        }
        .frame(width: 400, height: 500)
        #endif
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            // Search/Add field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search or create tag...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if !searchText.isEmpty {
                            Task {
                                await createAndAttachTag(searchText)
                            }
                        }
                    }
                    .onChange(of: searchText) { newValue in
                        // Cancel previous search task
                        searchTask?.cancel()
                        
                        // Start new search task with debounce
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                            
                            if !Task.isCancelled {
                                await searchTags(newValue)
                            }
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        filteredTags = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
            #else
            .background(Color(UIColor.systemGray6))
            #endif
            
            if isLoading {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Show search results or suggestions
                        if !searchText.isEmpty {
                            if !tagExists(searchText) {
                                // Show create new tag option
                                Button(action: {
                                    Task {
                                        await createAndAttachTag(searchText)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Create \"\(searchText)\"")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                #if os(macOS)
                                .onHover { isHovered in
                                    if isHovered {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                #endif
                                
                                Divider()
                                    .padding(.horizontal)
                            }
                            
                            // Show filtered tags
                            ForEach(filteredTags) { tag in
                                tagRow(tag)
                            }
                        }
                        
                        // Show current node tags
                        if !nodeTags.isEmpty {
                            Text("Current Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, searchText.isEmpty ? 0 : 8)
                            
                            ForEach(nodeTags) { tag in
                                tagRow(tag)
                            }
                        }
                        
                        // Show all available tags if no search
                        if searchText.isEmpty && !availableTags.isEmpty {
                            Text("Available Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, nodeTags.isEmpty ? 0 : 8)
                            
                            ForEach(availableTags.filter { tag in
                                !nodeTags.contains(where: { $0.id == tag.id })
                            }) { tag in
                                tagRow(tag)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
        }
        .task {
            await loadTags()
        }
    }
    
    private func tagRow(_ tag: Tag) -> some View {
        Button(action: {
            Task {
                await toggleTag(tag)
            }
        }) {
            HStack {
                // Tag color indicator
                Circle()
                    .fill(tag.displayColor)
                    .frame(width: 12, height: 12)
                
                Text(tag.name)
                    .foregroundColor(.primary)
                
                if let description = tag.description, !description.isEmpty {
                    Text("• \(description)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Show checkmark if tag is attached to node
                if nodeTags.contains(where: { $0.id == tag.id }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }
    
    private func tagExists(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return availableTags.contains { $0.name.lowercased() == lowercasedName } ||
               filteredTags.contains { $0.name.lowercased() == lowercasedName }
    }
    
    private func loadTags() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let api = APIClient.shared
            
            // Load all available tags
            availableTags = try await api.getTags()
            
            // Load tags attached to this node
            nodeTags = node.tags // Use the tags already on the node
            
            logger.log("✅ Loaded \(availableTags.count) available tags, \(nodeTags.count) attached", category: "TagPickerView")
        } catch {
            errorMessage = "Failed to load tags: \(error.localizedDescription)"
            logger.log("❌ Failed to load tags: \(error)", level: .error, category: "TagPickerView")
        }
        
        isLoading = false
    }
    
    private func searchTags(_ query: String) async {
        guard !query.isEmpty else {
            filteredTags = []
            return
        }
        
        do {
            let api = APIClient.shared
            filteredTags = try await api.searchTags(query: query, limit: 10)
            logger.log("✅ Found \(filteredTags.count) tags for query: \(query)", category: "TagPickerView")
        } catch {
            logger.log("❌ Failed to search tags: \(error)", level: .error, category: "TagPickerView")
            // Fall back to local filtering
            let lowercasedQuery = query.lowercased()
            filteredTags = availableTags.filter { 
                $0.name.lowercased().contains(lowercasedQuery) ||
                ($0.description?.lowercased().contains(lowercasedQuery) ?? false)
            }
        }
    }
    
    private func toggleTag(_ tag: Tag) async {
        do {
            let api = APIClient.shared
            
            if nodeTags.contains(where: { $0.id == tag.id }) {
                // Detach tag
                try await api.detachTagFromNode(nodeId: node.id, tagId: tag.id)
                nodeTags.removeAll { $0.id == tag.id }
                logger.log("✅ Detached tag: \(tag.name)", category: "TagPickerView")
            } else {
                // Attach tag
                try await api.attachTagToNode(nodeId: node.id, tagId: tag.id)
                nodeTags.append(tag)
                logger.log("✅ Attached tag: \(tag.name)", category: "TagPickerView")
            }
        } catch {
            errorMessage = "Failed to update tag: \(error.localizedDescription)"
            logger.log("❌ Failed to toggle tag: \(error)", level: .error, category: "TagPickerView")
        }
    }
    
    private func createAndAttachTag(_ name: String) async {
        do {
            let api = APIClient.shared
            
            // Create or get existing tag
            let tag = try await api.createTag(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            
            // Attach to node if not already attached
            if !nodeTags.contains(where: { $0.id == tag.id }) {
                try await api.attachTagToNode(nodeId: node.id, tagId: tag.id)
                nodeTags.append(tag)
                
                // Add to available tags if not there
                if !availableTags.contains(where: { $0.id == tag.id }) {
                    availableTags.append(tag)
                }
            }
            
            // Clear search
            searchText = ""
            filteredTags = []
            
            logger.log("✅ Created and attached tag: \(tag.name)", category: "TagPickerView")
        } catch {
            errorMessage = "Failed to create tag: \(error.localizedDescription)"
            logger.log("❌ Failed to create tag: \(error)", level: .error, category: "TagPickerView")
        }
    }
}