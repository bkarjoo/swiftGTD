import Foundation
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - Transferable Conformance for Drag & Drop

extension Node: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// Extensions for offline support
public extension Node {
    /// Create a new Node with dates as strings (for offline creation)
    init(
        id: String,
        title: String,
        nodeType: String,
        parentId: String? = nil,
        ownerId: String = "",  // Will be filled during sync
        sortOrder: Int,
        createdAt: Date,
        updatedAt: Date,
        isList: Bool = false,
        childrenCount: Int = 0,
        tags: [Tag] = [],
        taskData: TaskData? = nil,
        noteData: NoteData? = nil,
        templateData: TemplateData? = nil,
        smartFolderData: SmartFolderData? = nil,
        folderData: FolderData? = nil
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        self.id = id
        self.title = title
        self.nodeType = nodeType
        self.parentId = parentId
        self.ownerId = ownerId
        self.sortOrder = sortOrder
        self.createdAt = formatter.string(from: createdAt)
        self.updatedAt = formatter.string(from: updatedAt)
        self.isList = isList
        self.childrenCount = childrenCount
        self.tags = tags
        self.taskData = taskData
        self.noteData = noteData
        self.templateData = templateData
        self.smartFolderData = smartFolderData
        self.folderData = folderData
    }
    
    /// Create a copy with updated fields (for offline updates)
    func copyWith(
        title: String? = nil,
        updatedAt: Date? = nil,
        taskData: TaskData? = nil,
        folderData: FolderData? = nil
    ) -> Node {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return Node(
            id: self.id,
            title: title ?? self.title,
            nodeType: self.nodeType,
            parentId: self.parentId,
            ownerId: self.ownerId,
            createdAt: self.createdAt,
            updatedAt: formatter.string(from: updatedAt ?? Date()),
            sortOrder: self.sortOrder,
            isList: self.isList,
            childrenCount: self.childrenCount,
            tags: self.tags,
            taskData: taskData ?? self.taskData,
            noteData: self.noteData,
            templateData: self.templateData,
            smartFolderData: self.smartFolderData,
            folderData: folderData ?? self.folderData
        )
    }
    
    /// Parse date from string
    func parsedCreatedAt() -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
    }
    
    func parsedUpdatedAt() -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updatedAt)
    }
}

// TaskData extensions for mutability
public extension TaskData {
    func copyWith(
        status: String? = nil,
        completedAt: Date? = nil
    ) -> TaskData {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return TaskData(
            description: self.description,
            status: status ?? self.status,
            priority: self.priority,
            dueAt: self.dueAt,
            earliestStartAt: self.earliestStartAt,
            completedAt: completedAt != nil ? formatter.string(from: completedAt!) : nil,
            archived: self.archived
        )
    }
}
