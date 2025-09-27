import Foundation

public struct Node: Codable, Identifiable {
    public let id: String
    public let title: String
    public let nodeType: String
    public let parentId: String?
    public let ownerId: String
    public let createdAt: String
    public let updatedAt: String
    public let sortOrder: Int
    public let isList: Bool
    public let childrenCount: Int
    public let tags: [Tag]
    
    // Type-specific data
    public let taskData: TaskData?
    public let noteData: NoteData?
    public let templateData: TemplateData?
    public let smartFolderData: SmartFolderData?
    public let folderData: FolderData?
    
    public init(
        id: String,
        title: String,
        nodeType: String,
        parentId: String? = nil,
        ownerId: String,
        createdAt: String,
        updatedAt: String,
        sortOrder: Int,
        isList: Bool = false,
        childrenCount: Int = 0,
        tags: [Tag] = [],
        taskData: TaskData? = nil,
        noteData: NoteData? = nil,
        templateData: TemplateData? = nil,
        smartFolderData: SmartFolderData? = nil,
        folderData: FolderData? = nil
    ) {
        self.id = id
        self.title = title
        self.nodeType = nodeType
        self.parentId = parentId
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isList = isList
        self.childrenCount = childrenCount
        self.tags = tags
        self.taskData = taskData
        self.noteData = noteData
        self.templateData = templateData
        self.smartFolderData = smartFolderData
        self.folderData = folderData
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case nodeType = "node_type"
        case parentId = "parent_id"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sortOrder = "sort_order"
        case isList = "is_list"
        case childrenCount = "children_count"
        case tags
        case taskData = "task_data"
        case noteData = "note_data"
        case templateData = "template_data"
        case smartFolderData = "smart_folder_data"
        case folderData = "folder_data"
    }
}

public struct TaskData: Codable {
    public let description: String?
    public let status: String?
    public let priority: String?
    public let dueAt: String?
    public let earliestStartAt: String?
    public let completedAt: String?
    public let archived: Bool?
    
    public init(
        description: String? = nil,
        status: String? = nil,
        priority: String? = nil,
        dueAt: String? = nil,
        earliestStartAt: String? = nil,
        completedAt: String? = nil,
        archived: Bool? = nil
    ) {
        self.description = description
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
        self.earliestStartAt = earliestStartAt
        self.completedAt = completedAt
        self.archived = archived
    }
    
    enum CodingKeys: String, CodingKey {
        case description
        case status
        case priority
        case dueAt = "due_at"
        case earliestStartAt = "earliest_start_at"
        case completedAt = "completed_at"
        case archived
    }
}

public struct NoteData: Codable {
    public let body: String?
    
    public init(body: String? = nil) {
        self.body = body
    }
}

public struct TemplateData: Codable {
    public let description: String?
    public let category: String?
    public let usageCount: Int?
    public let targetNodeId: String?
    public let createContainer: Bool?
    
    enum CodingKeys: String, CodingKey {
        case description
        case category
        case usageCount = "usage_count"
        case targetNodeId = "target_node_id"
        case createContainer = "create_container"
    }
}

public struct SmartFolderData: Codable {
    public let ruleId: String?
    public let autoRefresh: Bool?
    public let description: String?
    // Note: Legacy 'rules' field removed - we only use ruleId now

    public init(ruleId: String? = nil, autoRefresh: Bool? = nil, description: String? = nil) {
        self.ruleId = ruleId
        self.autoRefresh = autoRefresh
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case autoRefresh = "auto_refresh"
        case description
    }
}

public struct FolderData: Codable {
    public let description: String?

    public init(description: String? = nil) {
        self.description = description
    }
}

public enum NodeType: String, Codable, CaseIterable {
    case task = "task"
    case project = "project"
    case area = "area"
    case note = "note"
    case folder = "folder"
    
    public var displayName: String {
        switch self {
        case .task: return "Task"
        case .project: return "Project"
        case .area: return "Area"
        case .note: return "Note"
        case .folder: return "Folder"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .area: return "tray.full"
        case .note: return "note.text"
        case .folder: return "folder"
        }
    }
}