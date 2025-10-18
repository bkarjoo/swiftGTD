import SwiftUI
import Core
import Models
import Services
import Networking
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let logger = Logger.shared

/// A markdown editor view for editing and viewing note nodes.
/// Provides edit and render modes with basic markdown support.
///
/// Features:
/// - Edit mode with plain text editor
/// - View mode with markdown rendering
/// - Automatic save tracking
/// - Platform-specific styling
public struct NoteEditorView: View {
    let node: Node
    let embeddedMode: Bool
    let onDismiss: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataManager: DataManager

    @State private var noteContent: String = ""
    @State private var originalContent: String = ""
    @State private var editMode: EditMode = .inactive
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var hasUnsavedChanges = false
    @State private var showingHelp = false
    @FocusState private var isTextEditorFocused: Bool

    public init(node: Node, embeddedMode: Bool = false, onDismiss: @escaping () async -> Void = { }) {
        self.node = node
        self.embeddedMode = embeddedMode
        self.onDismiss = onDismiss
    }

    enum EditMode {
        case active
        case inactive
    }

    public var body: some View {
        Group {
            if embeddedMode {
                // In embedded mode, no navigation wrapper or size constraints
                noteEditorContent
            } else {
                // Regular modal mode
                #if os(iOS)
                NavigationView {
                    noteEditorContent
                }
                .navigationViewStyle(StackNavigationViewStyle())
                #else
                noteEditorContent
                    .frame(minWidth: 700, idealWidth: 900, maxWidth: .infinity,
                           minHeight: 500, idealHeight: 700, maxHeight: .infinity)
                #endif
            }
        }
        .onAppear {
            loadNoteContent()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: noteContent) { _ in
            // Only mark as changed if content differs from original
            hasUnsavedChanges = (noteContent != originalContent)
        }
    }

    @ViewBuilder
    private var noteEditorContent: some View {
        VStack(spacing: 0) {
            // Header with close button and title
            HStack {
                if !embeddedMode {
                    Text(node.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                Spacer()

                // Mode toggle
                Picker("Mode", selection: $editMode) {
                    Text("View").tag(EditMode.inactive)
                    Text("Edit").tag(EditMode.active)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
                .onChange(of: editMode) { newMode in
                    logger.log("🔄 Edit mode changed to: \(newMode == .active ? "Edit" : "View")", category: "NoteEditor")
                }

                // Action buttons
                HStack(spacing: 12) {
                    if hasUnsavedChanges {
                        Button(action: {
                            logger.log("🔘 Save button clicked", category: "NoteEditor")
                            Task {
                                await saveNote()
                            }
                        }) {
                            Label("Save", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                        .keyboardShortcut("s", modifiers: .command)
                    }

                    Button(action: {
                        showingHelp.toggle()
                    }) {
                        Label("Help", systemImage: "questionmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("h", modifiers: .command)
                    .popover(isPresented: $showingHelp) {
                        helpContent
                    }

                    if !embeddedMode {
                        Button(action: {
                            logger.log("🔙 Closing note editor", category: "NoteEditor")
                            Task {
                                await onDismiss()
                                dismiss()
                            }
                        }) {
                            Label("Close", systemImage: "xmark.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
            #else
            .background(Color(UIColor.systemGroupedBackground))
            #endif

            Divider()

            // Content area
            if editMode == .active {
                // Edit mode - plain text editor
                TextEditor(text: $noteContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .focused($isTextEditorFocused)
            } else {
                // Render mode - markdown preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if noteContent.isEmpty {
                            Text("No content")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            MarkdownView(content: noteContent)
                                .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(
            // Hidden buttons for keyboard shortcuts
            Group {
                // Cmd+E: Enter edit mode (only active in view mode)
                if editMode == .inactive {
                    Button("") {
                        editMode = .active
                        // Focus TextEditor after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTextEditorFocused = true
                        }
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .hidden()

                    // Cmd+C: Copy entire note content (only active in view mode)
                    Button("") {
                        logger.log("📋 Copying note content to clipboard", category: "NoteEditor")
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(noteContent, forType: .string)
                        #else
                        UIPasteboard.general.string = noteContent
                        #endif
                        logger.log("✅ Note content copied to clipboard", category: "NoteEditor")
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    .hidden()
                }

                // Cmd+R: Discard changes (only active in edit mode)
                if editMode == .active {
                    Button("") {
                        // Discard changes and return to view mode
                        noteContent = originalContent
                        hasUnsavedChanges = false
                        editMode = .inactive
                        isTextEditorFocused = false
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .hidden()
                }
            }
        )
    }

    @ViewBuilder
    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard Shortcuts")
                .font(.headline)
                .padding(.bottom, 5)

            VStack(alignment: .leading, spacing: 6) {
                shortcutRow("⌘E", "Enter edit mode")
                shortcutRow("⌘R", "Discard & return to view")
                shortcutRow("⌘S", "Save changes")
                shortcutRow("⌘C", "Copy note to clipboard")
                shortcutRow("⌘H", "Show/hide help")
                shortcutRow("Esc", "Close editor")
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding()
        .frame(width: 250)
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .foregroundColor(.blue)
                .frame(width: 50, alignment: .leading)
            Text(description)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    /// Loads the note content from the node's noteData.
    /// Called when the view appears to initialize the editor with existing content.
    private func loadNoteContent() {
        logger.log("📞 loadNoteContent called", category: "NoteEditor")
        logger.log("📄 Loading note content for node: \(node.id) - \(node.title)", category: "NoteEditor")

        let content = node.noteData?.body ?? ""
        noteContent = content
        originalContent = content  // Store the original for comparison

        logger.log("✅ Loaded \(content.count) characters", category: "NoteEditor")
        logger.log("   Content preview: \(String(content.prefix(100)))...", category: "NoteEditor")
    }

    /// Saves the note content back to the server.
    /// Updates the node with new note content and switches back to view mode on success.
    private func saveNote() async {
        logger.log("📞 saveNote called", category: "NoteEditor")
        logger.log("💾 Preparing to save note for node: \(node.id) - \(node.title)", category: "NoteEditor")
        logger.log("   Content length: \(noteContent.count) characters", category: "NoteEditor")

        isSaving = true

        let update = NodeUpdate(
            title: node.title,
            parentId: node.parentId,
            sortOrder: node.sortOrder,
            noteData: NoteDataUpdate(body: noteContent)
        )

        logger.log("🌐 Calling DataManager to update node: \(node.id)", category: "NoteEditor")

        // Use DataManager which handles both online and offline scenarios
        if let updatedNode = await dataManager.updateNode(node.id, update: update) {
            logger.log("✅ Note saved successfully", category: "NoteEditor")
            logger.log("   Updated node ID: \(updatedNode.id)", category: "NoteEditor")
            logger.log("   New content length: \(updatedNode.noteData?.body?.count ?? 0)", category: "NoteEditor")

            // Update original content to match saved content
            originalContent = noteContent

            // Clear unsaved changes flag and switch to view mode
            logger.log("🔄 Clearing unsaved changes flag", category: "NoteEditor")
            hasUnsavedChanges = false

            logger.log("🔄 Switching to view mode", category: "NoteEditor")
            editMode = .inactive
        } else {
            // When offline, DataManager now returns an optimistic update
            // This shouldn't happen anymore, but handle it just in case
            logger.log("⚠️ Note update returned nil - might be offline", category: "NoteEditor")

            // Still update UI optimistically
            originalContent = noteContent
            hasUnsavedChanges = false
            editMode = .inactive

            // Could show a subtle indicator that this is pending sync
        }

        isSaving = false
        logger.log("✅ saveNote completed", category: "NoteEditor")
    }
}

// MARK: - MarkdownView

/// A view that renders basic markdown formatting.
/// Supports headers, bullet points, quotes, code blocks, and inline formatting.
struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdown(content), id: \.self) { element in
                renderElement(element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parses markdown text into structured elements for rendering.
    /// Supports headers (#, ##, ###), bullet points (-, *), quotes (>), and code blocks (```).
    /// - Parameter text: The markdown text to parse
    /// - Returns: Array of parsed markdown elements
    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("# ") {
                elements.append(.heading1(String(line.dropFirst(2))))
            } else if line.hasPrefix("## ") {
                elements.append(.heading2(String(line.dropFirst(3))))
            } else if line.hasPrefix("### ") {
                elements.append(.heading3(String(line.dropFirst(4))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                elements.append(.bulletPoint(String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                elements.append(.quote(String(line.dropFirst(2))))
            } else if line.hasPrefix("```") {
                elements.append(.codeBlock(line))
            } else if line.isEmpty {
                elements.append(.empty)
            } else {
                elements.append(.paragraph(line))
            }
        }

        return elements
    }

    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .heading1(let text):
            Text(text)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.vertical, 4)

        case .heading2(let text):
            Text(text)
                .font(.title)
                .fontWeight(.semibold)
                .padding(.vertical, 2)

        case .heading3(let text):
            Text(text)
                .font(.title2)
                .fontWeight(.medium)
                .padding(.vertical, 1)

        case .paragraph(let text):
            renderInlineMarkdown(text)
                .fixedSize(horizontal: false, vertical: true)

        case .bulletPoint(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .fontWeight(.bold)
                renderInlineMarkdown(text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 3)
                renderInlineMarkdown(text)
                    .italic()
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)

        case .empty:
            Text(" ")
                .font(.caption)
        }
    }

    /// Renders inline markdown formatting such as bold (**text**), italic (*text*), and code (`text`).
    /// Currently provides basic formatting - full inline rendering to be implemented.
    /// - Parameter text: The text containing inline markdown
    /// - Returns: SwiftUI Text view with appropriate formatting
    private func renderInlineMarkdown(_ text: String) -> Text {
        var result = Text("")
        var currentText = text

        // Simple rendering - just display the text as-is for now
        // TODO: Add proper markdown inline rendering
        result = Text(currentText)

        // Apply basic formatting based on simple patterns
        if currentText.contains("**") {
            // Has bold text
            let cleaned = currentText.replacingOccurrences(of: "**", with: "")
            result = Text(cleaned).fontWeight(.bold)
        } else if currentText.contains("*") {
            // Has italic text
            let cleaned = currentText.replacingOccurrences(of: "*", with: "")
            result = Text(cleaned).italic()
        } else if currentText.contains("`") {
            // Has code text
            let cleaned = currentText.replacingOccurrences(of: "`", with: "")
            result = Text(cleaned).font(.system(.body, design: .monospaced))
        }

        return result
    }

    enum MarkdownElement: Hashable {
        case heading1(String)
        case heading2(String)
        case heading3(String)
        case paragraph(String)
        case bulletPoint(String)
        case quote(String)
        case codeBlock(String)
        case empty
    }
}