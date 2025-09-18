import Foundation

/// Update request for modifying an existing node
public struct NodeUpdate: Codable {
    public let title: String
    public let parentId: String?
    public let sortOrder: Int
    public let taskData: TaskDataUpdate?
    public let noteData: NoteDataUpdate?
    public let templateData: TemplateDataUpdate?
    public let smartFolderData: SmartFolderDataUpdate?
    
    enum CodingKeys: String, CodingKey {
        case title
        case parentId = "parent_id"
        case sortOrder = "sort_order"
        case taskData = "task_data"
        case noteData = "note_data"
        case templateData = "template_data"
        case smartFolderData = "smart_folder_data"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        // Explicitly encode nil for parent_id when moving to root
        try container.encode(parentId, forKey: .parentId)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(taskData, forKey: .taskData)
        try container.encodeIfPresent(noteData, forKey: .noteData)
        try container.encodeIfPresent(templateData, forKey: .templateData)
        try container.encodeIfPresent(smartFolderData, forKey: .smartFolderData)
    }
    
    public init(
        title: String,
        parentId: String?,
        sortOrder: Int,
        taskData: TaskDataUpdate? = nil,
        noteData: NoteDataUpdate? = nil,
        templateData: TemplateDataUpdate? = nil,
        smartFolderData: SmartFolderDataUpdate? = nil
    ) {
        self.title = title
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.taskData = taskData
        self.noteData = noteData
        self.templateData = templateData
        self.smartFolderData = smartFolderData
    }
}

/// Update data for task-specific fields
public struct TaskDataUpdate: Codable {
    public let status: String?
    public let priority: String?
    public let description: String?
    public let dueAt: String?
    public let earliestStartAt: String?
    public let completedAt: String?
    public let archived: Bool?
    
    enum CodingKeys: String, CodingKey {
        case status
        case priority
        case description
        case dueAt = "due_at"
        case earliestStartAt = "earliest_start_at"
        case completedAt = "completed_at"
        case archived
    }
    
    public init(
        status: String? = nil,
        priority: String? = nil,
        description: String? = nil,
        dueAt: String? = nil,
        earliestStartAt: String? = nil,
        completedAt: String? = nil,
        archived: Bool? = nil
    ) {
        self.status = status
        self.priority = priority
        self.description = description
        self.dueAt = dueAt
        self.earliestStartAt = earliestStartAt
        self.completedAt = completedAt
        self.archived = archived
    }
}

/// Update data for note-specific fields  
public struct NoteDataUpdate: Codable {
    public let body: String?
    
    public init(body: String?) {
        self.body = body
    }
}

/// Update data for template-specific fields
public struct TemplateDataUpdate: Codable {
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
    
    public init(
        description: String? = nil,
        category: String? = nil,
        usageCount: Int? = nil,
        targetNodeId: String? = nil,
        createContainer: Bool? = nil
    ) {
        self.description = description
        self.category = category
        self.usageCount = usageCount
        self.targetNodeId = targetNodeId
        self.createContainer = createContainer
    }
}

/// Update data for smart folder-specific fields
public struct SmartFolderDataUpdate: Codable {
    public let ruleId: String?
    public let autoRefresh: Bool?
    public let description: String?
    
    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case autoRefresh = "auto_refresh"
        case description
    }
    
    public init(
        ruleId: String? = nil,
        autoRefresh: Bool? = nil,
        description: String? = nil
    ) {
        self.ruleId = ruleId
        self.autoRefresh = autoRefresh
        self.description = description
    }
}