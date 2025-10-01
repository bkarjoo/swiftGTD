import SwiftUI
import Models
import Services
import Core
#if os(macOS)
import AppKit
#endif

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
    @State private var selectedIndex = 0
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    #if os(macOS)
    @State private var keyEventMonitor: Any?
    #endif

    // Debounce timer for search
    @State private var searchTask: Task<Void, Never>?
    
    public init(node: Node, onDismiss: @escaping () async -> Void) {
        self.node = node
        self.onDismiss = onDismiss
    }

    // Computed property for all visible tags in order
    private var allVisibleTags: [Tag] {
        var tags: [Tag] = []

        if !searchText.isEmpty {
            // Add create option if tag doesn't exist
            if !tagExists(searchText) {
                // Use a placeholder tag for the create option
                let createTag = Tag(id: "create-new", name: searchText, color: "#00FF00", description: "Create new tag", createdAt: nil)
                tags.append(createTag)
            }
            tags.append(contentsOf: filteredTags)
        }

        // Current tags
        tags.append(contentsOf: nodeTags)

        // Available tags not attached
        if searchText.isEmpty {
            let unattachedTags = availableTags.filter { tag in
                !nodeTags.contains(where: { $0.id == tag.id })
            }
            tags.append(contentsOf: unattachedTags)
        }

        return tags
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
        .onAppear {
            searchFieldFocused = true
            #if os(macOS)
            setupKeyEventMonitor()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            removeKeyEventMonitor()
            #endif
        }
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
                    .focused($searchFieldFocused)
                    .onSubmit {
                        if !searchText.isEmpty && allVisibleTags.isEmpty {
                            Task {
                                await createAndAttachTag(searchText)
                            }
                        } else if selectedIndex < allVisibleTags.count {
                            Task {
                                await handleTagSelection(at: selectedIndex)
                            }
                        }
                    }
                    .onChange(of: searchText) { newValue in
                        // Cancel previous search task
                        searchTask?.cancel()

                        // Reset selection when searching
                        selectedIndex = 0

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
                        // Show search results or create option
                        if !searchText.isEmpty {
                            if !tagExists(searchText) {
                                // Show create new tag option
                                let isSelected = selectedIndex == 0
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
                                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .padding(.horizontal)
                            }
                        }

                        // Group tags by sections
                        let searchTags = !searchText.isEmpty ? filteredTags : []
                        let currentTags = nodeTags
                        let availableTags = searchText.isEmpty ?
                            self.availableTags.filter { tag in
                                !nodeTags.contains(where: { $0.id == tag.id })
                            } : []

                        // Show search results
                        if !searchTags.isEmpty {
                            ForEach(Array(searchTags.enumerated()), id: \.element.id) { index, tag in
                                let globalIndex = index + (!searchText.isEmpty && !tagExists(searchText) ? 1 : 0)
                                tagRowWithSelection(tag, isSelected: selectedIndex == globalIndex, index: globalIndex)
                            }
                        }

                        // Show current node tags
                        if !currentTags.isEmpty && searchText.isEmpty {
                            Text("Current Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 0)

                            ForEach(Array(currentTags.enumerated()), id: \.element.id) { index, tag in
                                let globalIndex = index + searchTags.count + (!searchText.isEmpty && !tagExists(searchText) ? 1 : 0)
                                tagRowWithSelection(tag, isSelected: selectedIndex == globalIndex, index: globalIndex)
                            }
                        }

                        // Show available tags
                        if !availableTags.isEmpty {
                            Text("Available Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, currentTags.isEmpty ? 0 : 8)

                            ForEach(Array(availableTags.enumerated()), id: \.element.id) { index, tag in
                                let globalIndex = index + searchTags.count + currentTags.count + (!searchText.isEmpty && !tagExists(searchText) ? 1 : 0)
                                tagRowWithSelection(tag, isSelected: selectedIndex == globalIndex, index: globalIndex)
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
    
    private func tagRowWithSelection(_ tag: Tag, isSelected: Bool, index: Int) -> some View {
        Button(action: {
            Task {
                await handleTagSelection(at: index)
            }
        }) {
            HStack {
                // Tag color indicator
                Circle()
                    .fill(tag.displayColor)
                    .frame(width: 12, height: 12)

                Text(tag.name)
                    .foregroundColor(.primary)

                if tag.id != "create-new", let description = tag.description, !description.isEmpty {
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
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered in
            if isHovered {
                selectedIndex = index
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
            // Load all available tags
            availableTags = try await dataManager.getTags()
            
            // Load tags attached to this node
            nodeTags = node.tags // Use the tags already on the node
            
            logger.log("✅ Loaded \(availableTags.count) available tags, \(nodeTags.count) attached", category: "TagPickerView")
        } catch {
            errorMessage = "Failed to load tags: \(error.localizedDescription)"
            logger.log("❌ Failed to load tags: \(error)", category: "TagPickerView", level: .error)
        }
        
        isLoading = false
    }
    
    private func searchTags(_ query: String) async {
        guard !query.isEmpty else {
            filteredTags = []
            return
        }
        
        do {
            filteredTags = try await dataManager.searchTags(query: query, limit: 10)
            logger.log("✅ Found \(filteredTags.count) tags for query: \(query)", category: "TagPickerView")
        } catch {
            logger.log("❌ Failed to search tags: \(error)", category: "TagPickerView", level: .error)
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
            if nodeTags.contains(where: { $0.id == tag.id }) {
                // Detach tag
                try await dataManager.detachTagFromNode(nodeId: node.id, tagId: tag.id)
                nodeTags.removeAll { $0.id == tag.id }
                logger.log("✅ Detached tag: \(tag.name)", category: "TagPickerView")
            } else {
                // Attach tag
                try await dataManager.attachTagToNode(nodeId: node.id, tagId: tag.id)
                nodeTags.append(tag)
                logger.log("✅ Attached tag: \(tag.name)", category: "TagPickerView")
            }
        } catch {
            errorMessage = "Failed to update tag: \(error.localizedDescription)"
            logger.log("❌ Failed to toggle tag: \(error)", category: "TagPickerView", level: .error)
        }
    }
    
    private func createAndAttachTag(_ name: String) async {
        do {
            // Create or get existing tag
            let tag = try await dataManager.createTag(name: name.trimmingCharacters(in: .whitespacesAndNewlines))

            // Attach to node if not already attached
            if !nodeTags.contains(where: { $0.id == tag.id }) {
                try await dataManager.attachTagToNode(nodeId: node.id, tagId: tag.id)
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
            logger.log("❌ Failed to create tag: \(error)", category: "TagPickerView", level: .error)
        }
    }

    #if os(macOS)
    private func setupKeyEventMonitor() {
        removeKeyEventMonitor()

        logger.log("🎹 Setting up key event monitor for TagPicker", category: "TagPickerView")

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check if we should handle this key
            let shouldHandle = self.shouldHandleKeyEvent(event)

            logger.log("🎹 Key event: \(event.keyCode), shouldHandle: \(shouldHandle)", category: "TagPickerView")

            if shouldHandle {
                return self.handleKeyEvent(event) ? nil : event
            } else {
                return event
            }
        }
    }

    private func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125, 126: // Arrow keys - always handle
            return true
        case 49: // Space - always handle
            return true
        case 53: // Escape - always handle
            return true
        case 36: // Return - only handle if NOT in search field
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSTextView || firstResponder is NSTextField {
                return false // Let the text field's onSubmit handle it
            }
            return true
        default:
            return false
        }
    }

    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let tags = allVisibleTags

        logger.log("🎹 TagPicker handling key: \(event.keyCode)", category: "TagPickerView")

        switch event.keyCode {
        case 125: // Down arrow
            if !tags.isEmpty {
                selectedIndex = min(selectedIndex + 1, tags.count - 1)
                logger.log("⬇️ Down arrow: selectedIndex = \(selectedIndex)", category: "TagPickerView")
            }
            return true

        case 126: // Up arrow
            if !tags.isEmpty {
                selectedIndex = max(selectedIndex - 1, 0)
                logger.log("⬆️ Up arrow: selectedIndex = \(selectedIndex)", category: "TagPickerView")
            }
            return true

        case 49, 36: // Space or Return
            logger.log("⏎ Space/Return: selecting tag at index \(selectedIndex)", category: "TagPickerView")
            if selectedIndex < tags.count {
                Task {
                    await handleTagSelection(at: selectedIndex)
                }
            }
            return true

        case 53: // Escape
            logger.log("⎋ Escape: dismissing tag picker", category: "TagPickerView")
            Task {
                await onDismiss()
                dismiss()
            }
            return true

        default:
            return false
        }
    }
    #endif

    private func handleTagSelection(at index: Int) async {
        let tags = allVisibleTags
        guard index < tags.count else { return }

        let tag = tags[index]

        if tag.id == "create-new" {
            await createAndAttachTag(searchText)
        } else {
            await toggleTag(tag)
        }
    }
}