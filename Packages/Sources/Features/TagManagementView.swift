import SwiftUI
import Models
import Services
import Core
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public struct TagManagementView: View {
    @EnvironmentObject private var dataManager: DataManager
    @AppStorage("treeFontSize") private var treeFontSize = 14
    @AppStorage("treeLineSpacing") private var treeLineSpacing = 4

    @State private var tags: [Tag] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateAlert = false
    @State private var newTagName = ""
    @State private var editingTag: Tag?
    @State private var editedTagName = ""
    @State private var tagToDelete: Tag?
    @State private var showingDeleteAlert = false

    private let logger = Logger.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Tag Management", systemImage: "tag.circle.fill")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: {
                    showingCreateAlert = true
                }) {
                    Label("New Tag", systemImage: "plus")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading tags...")
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else if tags.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 48))
                        .foregroundColor(Color.secondary)
                    Text("No tags yet")
                        .font(.headline)
                    Text("Create your first tag to get started")
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tags) { tag in
                            TagRow(
                                tag: tag,
                                isEditing: editingTag?.id == tag.id,
                                editedName: $editedTagName,
                                fontSize: treeFontSize,
                                lineSpacing: treeLineSpacing,
                                onEdit: { startEditingTag(tag) },
                                onSave: { saveEditedTag() },
                                onCancel: { cancelEditing() },
                                onDelete: { confirmDeleteTag(tag) }
                            )
                            Divider()
                        }
                    }
                }
            }

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(UIColor.systemBackground))
        #endif
        .onAppear {
            loadTags()
        }
        .alert("Create New Tag", isPresented: $showingCreateAlert) {
            TextField("Tag name", text: $newTagName)
            Button("Cancel", role: .cancel) {
                newTagName = ""
            }
            Button("Create") {
                createTag()
            }
        } message: {
            Text("Enter a name for the new tag")
        }
        .alert("Delete Tag", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                tagToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let tag = tagToDelete {
                    deleteTag(tag)
                }
            }
        } message: {
            if let tag = tagToDelete {
                Text("Are you sure you want to delete the tag \"\(tag.name)\"? This action cannot be undone.")
            }
        }
    }

    private func loadTags() {
        Task {
            isLoading = true
            errorMessage = nil

            do {
                tags = try await dataManager.getTags()
                // Sort alphabetically
                tags.sort { $0.name.lowercased() < $1.name.lowercased() }
            } catch {
                logger.log("❌ Failed to load tags: \(error)", category: "TagManagement", level: .error)
                errorMessage = "Failed to load tags"
            }

            isLoading = false
        }
    }

    private func createTag() {
        guard !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        Task {
            errorMessage = nil

            do {
                _ = try await dataManager.createTag(
                    name: newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                newTagName = ""
                await loadTags()
            } catch {
                logger.log("❌ Failed to create tag: \(error)", category: "TagManagement", level: .error)
                errorMessage = "Failed to create tag"
            }
        }
    }

    private func startEditingTag(_ tag: Tag) {
        editingTag = tag
        editedTagName = tag.name
    }

    private func saveEditedTag() {
        guard let tag = editingTag,
              !editedTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let trimmedName = editedTagName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't update if name hasn't changed
        if trimmedName == tag.name {
            cancelEditing()
            return
        }

        Task {
            errorMessage = nil

            do {
                let (updatedTag, wasMerged) = try await dataManager.updateTag(id: tag.id, name: trimmedName)

                // Check if tag was merged
                if wasMerged {
                    errorMessage = "Tag was merged with existing tag \"\(updatedTag.name)\""
                }

                cancelEditing()
                await loadTags()
            } catch {
                logger.log("❌ Failed to update tag: \(error)", category: "TagManagement", level: .error)
                errorMessage = "Failed to update tag: \(error.localizedDescription)"
                cancelEditing()
            }
        }
    }

    private func cancelEditing() {
        editingTag = nil
        editedTagName = ""
    }

    private func confirmDeleteTag(_ tag: Tag) {
        tagToDelete = tag
        showingDeleteAlert = true
    }

    private func deleteTag(_ tag: Tag) {
        Task {
            errorMessage = nil

            do {
                try await dataManager.deleteTag(id: tag.id)
                tagToDelete = nil
                await loadTags()
            } catch {
                logger.log("❌ Failed to delete tag: \(error)", category: "TagManagement", level: .error)
                errorMessage = "Failed to delete tag"
            }
        }
    }
}

// MARK: - Tag Row View

struct TagRow: View {
    let tag: Tag
    let isEditing: Bool
    @Binding var editedName: String
    let fontSize: Int
    let lineSpacing: Int
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Tag icon
            Image(systemName: "tag.fill")
                .foregroundColor(tag.displayColor)
                .font(.system(size: CGFloat(fontSize)))

            // Tag name or edit field
            if isEditing {
                TextField("Tag name", text: $editedName, onCommit: onSave)
                    .textFieldStyle(.plain)
                    .font(.system(size: CGFloat(fontSize)))

                // Save/Cancel buttons
                HStack(spacing: 8) {
                    Button(action: onSave) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: CGFloat(fontSize)))
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: CGFloat(fontSize)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(tag.name)
                    .font(.system(size: CGFloat(fontSize)))

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: CGFloat(fontSize)))
                    }
                    .buttonStyle(.plain)
                    .help("Edit tag name")

                    Button(action: onDelete) {
                        Image(systemName: "trash.circle")
                            .foregroundColor(.red)
                            .font(.system(size: CGFloat(fontSize)))
                    }
                    .buttonStyle(.plain)
                    .help("Delete tag")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, CGFloat(lineSpacing))
        .background(isEditing ? Color.blue.opacity(0.1) : Color.clear)
    }
}

// MARK: - Preview

#if DEBUG
struct TagManagementView_Previews: PreviewProvider {
    static var previews: some View {
        TagManagementView()
            .environmentObject(DataManager())
    }
}
#endif