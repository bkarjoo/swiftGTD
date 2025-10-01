import Foundation
import SwiftUI
import Models
import Services
import Core

@MainActor
public class NodeDetailsViewModel: ObservableObject {
    private let logger = Logger.shared
    
    // Node data
    @Published var node: Node?
    @Published var originalNode: Node?
    
    // Common editable fields
    @Published var title: String = ""
    @Published var parentId: String?
    @Published var sortOrder: Int = 0
    @Published var tags: [Tag] = []
    
    // Task-specific fields
    @Published var taskStatus: String = "todo"
    @Published var taskPriority: String = "medium"
    @Published var taskDescription: String = ""
    @Published var taskDueDate: Date?
    @Published var taskEarliestStartDate: Date?
    @Published var taskArchived: Bool = false
    
    // Note-specific fields
    @Published var noteBody: String = ""
    
    // Template-specific fields
    @Published var templateDescription: String = ""
    @Published var templateCategory: String = ""
    @Published var templateUsageCount: Int = 0
    @Published var templateTargetNodeId: String?
    @Published var templateCreateContainer: Bool = true
    
    // Smart Folder-specific fields
    @Published var smartFolderRuleId: String?
    @Published var smartFolderAutoRefresh: Bool = true
    @Published var smartFolderDescription: String = ""
    @Published var availableRules: [Rule] = []
    @Published var showingRulePicker = false

    // Folder-specific fields
    @Published var folderDescription: String = ""
    
    // UI State
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var hasChanges = false
    @Published var showingParentPicker = false
    @Published var showingTargetNodePicker = false
    @Published var showingTagPicker = false
    @Published var availableParents: [Node] = []
    
    // Dependencies
    private var dataManager: DataManager?
    private weak var treeViewModel: TreeViewModel?
    
    public init() {
        logger.log("📞 NodeDetailsViewModel initialized", category: "NodeDetailsViewModel")
    }
    
    public func setDataManager(_ manager: DataManager) {
        self.dataManager = manager
        logger.log("✅ DataManager set", category: "NodeDetailsViewModel")
    }

    public func setTreeViewModel(_ treeViewModel: TreeViewModel?) {
        self.treeViewModel = treeViewModel
        logger.log("✅ TreeViewModel set", category: "NodeDetailsViewModel")
    }
    
    public func loadNode(nodeId: String) async {
        logger.log("📞 Loading node: \(nodeId)", category: "NodeDetailsViewModel")
        isLoading = true
        errorMessage = nil
        
        do {
            guard let dataManager = dataManager else {
                logger.error("No DataManager available", category: "NodeDetailsViewModel")
                return
            }
            let loadedNode = try await dataManager.getNode(id: nodeId)
            
            await MainActor.run {
                self.node = loadedNode
                self.originalNode = loadedNode
                self.title = loadedNode.title
                self.parentId = loadedNode.parentId
                self.sortOrder = loadedNode.sortOrder
                self.tags = loadedNode.tags
                
                // Load task-specific fields if it's a task
                if loadedNode.nodeType == "task", let taskData = loadedNode.taskData {
                    self.taskStatus = taskData.status ?? "todo"
                    self.taskPriority = taskData.priority ?? "medium"
                    self.taskDescription = taskData.description ?? ""
                    self.taskArchived = taskData.archived ?? false
                    
                    // Parse dates from ISO strings
                    if let dueAt = taskData.dueAt {
                        self.taskDueDate = self.parseISO8601Date(dueAt)
                    }
                    if let earliestStartAt = taskData.earliestStartAt {
                        self.taskEarliestStartDate = self.parseISO8601Date(earliestStartAt)
                    }
                }
                
                // Load note-specific fields if it's a note
                if loadedNode.nodeType == "note", let noteData = loadedNode.noteData {
                    self.noteBody = noteData.body ?? ""
                }
                
                // Load template-specific fields if it's a template
                if loadedNode.nodeType == "template", let templateData = loadedNode.templateData {
                    self.templateDescription = templateData.description ?? ""
                    self.templateCategory = templateData.category ?? ""
                    self.templateUsageCount = templateData.usageCount ?? 0
                    self.templateTargetNodeId = templateData.targetNodeId
                    self.templateCreateContainer = templateData.createContainer ?? true
                }
                
                // Load smart folder-specific fields if it's a smart folder
                if loadedNode.nodeType == "smart_folder", let smartFolderData = loadedNode.smartFolderData {
                    self.smartFolderRuleId = smartFolderData.ruleId
                    self.smartFolderAutoRefresh = smartFolderData.autoRefresh ?? true
                    self.smartFolderDescription = smartFolderData.description ?? ""
                }

                // Load folder-specific fields if it's a folder
                if loadedNode.nodeType == "folder", let folderData = loadedNode.folderData {
                    self.folderDescription = folderData.description ?? ""
                }

                self.hasChanges = false
                logger.log("✅ Node loaded: \(loadedNode.title)", category: "NodeDetailsViewModel")
            }

            // Don't load available parents here - lazy load when needed
            // await loadAvailableParents()

            // Load available rules if it's a smart folder
            if loadedNode.nodeType == "smart_folder" {
                await loadAvailableRules()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                logger.log("❌ Failed to load node: \(error)", category: "NodeDetailsViewModel", level: .error)
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func loadAvailableRules() async {
        logger.log("📞 Loading available rules", category: "NodeDetailsViewModel")
        
        do {
            guard let dataManager = dataManager else {
                logger.error("No DataManager available", category: "NodeDetailsViewModel")
                return
            }
            let rules = try await dataManager.getRules(includePublic: true, includeSystem: true)

            await MainActor.run {
                self.availableRules = rules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                logger.log("✅ Loaded \(rules.count) available rules", category: "NodeDetailsViewModel")
            }
        } catch {
            logger.log("❌ Failed to load rules: \(error)", category: "NodeDetailsViewModel", level: .error)
            // Continue without rules - non-critical error
        }
    }
    
    public func loadAvailableParentsIfNeeded() async {
        // Only load if we haven't loaded yet
        if availableParents.isEmpty {
            await loadAvailableParents()
        }
    }

    private func loadAvailableParents() async {
        logger.log("📞 Loading available parents", category: "NodeDetailsViewModel")
        
        guard let dataManager = dataManager else {
            logger.log("❌ No DataManager available", category: "NodeDetailsViewModel", level: .error)
            return
        }
        
        // Get all nodes from DataManager
        let allNodes = dataManager.nodes
        
        // Filter out invalid parents
        var validParents: [Node] = []
        
        for potentialParent in allNodes {
            // Can't be its own parent
            if potentialParent.id == node?.id {
                continue
            }
            
            // Can't be a descendant
            if isDescendant(potentialParent.id, of: node?.id ?? "") {
                continue
            }
            
            // SMART FOLDER RULE 1: Smart folders cannot be parents of any node
            // Smart folders are virtual containers with dynamic content
            if potentialParent.nodeType == "smart_folder" {
                continue
            }

            // NOTE NODE RULE: Note nodes cannot be parents of any node
            // Notes are leaf nodes that only contain markdown content
            if potentialParent.nodeType == "note" {
                continue
            }

            // Some node types can only be under certain parents
            // For now, allow all combinations except tasks can't contain smart folders
            if node?.nodeType == "smart_folder" && potentialParent.nodeType == "task" {
                continue
            }
            
            validParents.append(potentialParent)
        }
        
        // Sort alphabetically
        validParents.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        
        await MainActor.run {
            self.availableParents = validParents
            logger.log("✅ Loaded \(validParents.count) available parents", category: "NodeDetailsViewModel")
        }
    }
    
    private func isDescendant(_ nodeId: String, of ancestorId: String) -> Bool {
        guard let dataManager = dataManager else { return false }
        
        // Check if nodeId is a descendant of ancestorId
        let children = dataManager.nodes.filter { $0.parentId == ancestorId }
        
        for child in children {
            if child.id == nodeId {
                return true
            }
            if isDescendant(nodeId, of: child.id) {
                return true
            }
        }
        
        return false
    }
    
    public func updateField<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<NodeDetailsViewModel, T>, value: T) {
        let oldValue = self[keyPath: keyPath]
        logger.log("📞 updateField called for keyPath", category: "NodeDetailsViewModel")
        logger.log("🔄 Field changing from: \(oldValue) to: \(value)", category: "NodeDetailsViewModel")
        self[keyPath: keyPath] = value
        checkForChanges()
    }
    
    public func checkForChanges() {
        logger.log("📞 checkForChanges called", category: "NodeDetailsViewModel")
        guard let originalNode = originalNode else {
            logger.log("⚠️ No original node to compare", category: "NodeDetailsViewModel")
            hasChanges = false
            return
        }
        
        hasChanges = title != originalNode.title ||
                    parentId != originalNode.parentId ||
                    sortOrder != originalNode.sortOrder
        
        // Check task-specific fields if it's a task
        if originalNode.nodeType == "task", let taskData = originalNode.taskData {
            hasChanges = hasChanges ||
                        taskStatus != (taskData.status ?? "todo") ||
                        taskPriority != (taskData.priority ?? "medium") ||
                        taskDescription != (taskData.description ?? "") ||
                        taskArchived != (taskData.archived ?? false)
            
            // Check dates
            let originalDueDate = taskData.dueAt.flatMap { parseISO8601Date($0) }
            let originalStartDate = taskData.earliestStartAt.flatMap { parseISO8601Date($0) }
            
            hasChanges = hasChanges ||
                        taskDueDate != originalDueDate ||
                        taskEarliestStartDate != originalStartDate
        }
        
        // Check note-specific fields if it's a note
        if originalNode.nodeType == "note", let noteData = originalNode.noteData {
            hasChanges = hasChanges ||
                        noteBody != (noteData.body ?? "")
        }
        
        // Check template-specific fields if it's a template
        if originalNode.nodeType == "template", let templateData = originalNode.templateData {
            hasChanges = hasChanges ||
                        templateDescription != (templateData.description ?? "") ||
                        templateCategory != (templateData.category ?? "") ||
                        templateUsageCount != (templateData.usageCount ?? 0) ||
                        templateTargetNodeId != templateData.targetNodeId ||
                        templateCreateContainer != (templateData.createContainer ?? true)
        }
        
        // Check smart folder-specific fields if it's a smart folder
        if originalNode.nodeType == "smart_folder", let smartFolderData = originalNode.smartFolderData {
            hasChanges = hasChanges ||
                        smartFolderRuleId != smartFolderData.ruleId ||
                        smartFolderAutoRefresh != (smartFolderData.autoRefresh ?? true) ||
                        smartFolderDescription != (smartFolderData.description ?? "")
        }

        // Check folder-specific fields if it's a folder
        if originalNode.nodeType == "folder", let folderData = originalNode.folderData {
            hasChanges = hasChanges ||
                        folderDescription != (folderData.description ?? "")
        }
        
        logger.log("🔄 Has changes: \(hasChanges)", category: "NodeDetailsViewModel")
    }
    
    private func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    private func formatISO8601Date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
    
    public func save() async {
        guard let node = node else { return }

        logger.log("📞 Saving node: \(node.id)", category: "NodeDetailsViewModel")

        // If parent is changing, move selection to the current parent before saving
        if parentId != originalNode?.parentId {
            logger.log("🎯 Parent changing from \(originalNode?.parentId ?? "nil") to \(parentId ?? "nil"), moving selection", category: "NodeDetailsViewModel")
            if let currentParentId = originalNode?.parentId {
                await MainActor.run {
                    treeViewModel?.selectedNodeId = currentParentId
                    logger.log("✅ Selection moved to parent node: \(currentParentId)", category: "NodeDetailsViewModel")
                }
            }
        }

        isSaving = true
        errorMessage = nil

        do {
            guard let dataManager = dataManager else {
                logger.error("No DataManager available for save", category: "NodeDetailsViewModel")
                return
            }

            // Create update request
            let taskDataUpdate: TaskDataUpdate?
            if node.nodeType == "task" {
                // Only send completedAt if status is done/completed
                let completedAt: String? = (taskStatus == "done" || taskStatus == "completed") 
                    ? (node.taskData?.completedAt ?? formatISO8601Date(Date()))
                    : nil
                
                taskDataUpdate = TaskDataUpdate(
                    status: taskStatus,
                    priority: taskPriority,
                    description: taskDescription.isEmpty ? nil : taskDescription,
                    dueAt: taskDueDate.map { formatISO8601Date($0) },
                    earliestStartAt: taskEarliestStartDate.map { formatISO8601Date($0) },
                    completedAt: completedAt,
                    archived: taskArchived
                )
            } else {
                taskDataUpdate = nil
            }
            
            // Create note data update if it's a note
            let noteDataUpdate: NoteDataUpdate?
            if node.nodeType == "note" {
                noteDataUpdate = NoteDataUpdate(
                    body: noteBody.isEmpty ? " " : noteBody  // API requires non-empty body
                )
            } else {
                noteDataUpdate = nil
            }
            
            // Create template data update if it's a template
            let templateDataUpdate: TemplateDataUpdate?
            if node.nodeType == "template" {
                templateDataUpdate = TemplateDataUpdate(
                    description: templateDescription.isEmpty ? nil : templateDescription,
                    category: templateCategory.isEmpty ? nil : templateCategory,
                    usageCount: templateUsageCount,
                    targetNodeId: templateTargetNodeId,
                    createContainer: templateCreateContainer
                )
            } else {
                templateDataUpdate = nil
            }
            
            // Create smart folder data update if it's a smart folder
            let smartFolderDataUpdate: SmartFolderDataUpdate?
            if node.nodeType == "smart_folder" {
                smartFolderDataUpdate = SmartFolderDataUpdate(
                    ruleId: smartFolderRuleId,
                    autoRefresh: smartFolderAutoRefresh,
                    description: smartFolderDescription.isEmpty ? nil : smartFolderDescription
                )
            } else {
                smartFolderDataUpdate = nil
            }

            // Create folder data update if it's a folder
            let folderDataUpdate: FolderDataUpdate?
            if node.nodeType == "folder" {
                folderDataUpdate = FolderDataUpdate(
                    description: folderDescription.isEmpty ? nil : folderDescription
                )
            } else {
                folderDataUpdate = nil
            }

            let nodeUpdate = NodeUpdate(
                title: title,
                parentId: parentId,
                sortOrder: sortOrder,
                taskData: taskDataUpdate,
                noteData: noteDataUpdate,
                templateData: templateDataUpdate,
                smartFolderData: smartFolderDataUpdate,
                folderData: folderDataUpdate
            )
            
            let updatedNode = try await dataManager.updateNode(id: node.id, update: nodeUpdate)
            
            await MainActor.run {
                self.node = updatedNode
                self.originalNode = updatedNode
                self.hasChanges = false
                
                // Update in DataManager and trigger refresh
                if let dataManager = self.dataManager {
                    if let index = dataManager.nodes.firstIndex(where: { $0.id == node.id }) {
                        dataManager.nodes[index] = updatedNode
                    }
                    // Trigger a full refresh to update the tree view
                    Task {
                        await dataManager.loadNodes()
                    }
                }
                
                logger.log("✅ Node saved successfully", category: "NodeDetailsViewModel")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                logger.log("❌ Failed to save node: \(error)", category: "NodeDetailsViewModel", level: .error)
            }
        }
        
        await MainActor.run {
            isSaving = false
        }
    }
    
    public func reloadTagsOnly(nodeId: String) async {
        logger.log("📞 Reloading tags only for node: \(nodeId)", category: "NodeDetailsViewModel")

        do {
            guard let dataManager = dataManager else {
                logger.error("No DataManager available", category: "NodeDetailsViewModel")
                return
            }
            let freshNode = try await dataManager.getNode(id: nodeId)

            await MainActor.run {
                // Update only the tags, preserving all other changes
                self.tags = freshNode.tags

                // Update the node with new tags while preserving its structure
                if let currentNode = self.node {
                    self.node = Node(
                        id: currentNode.id,
                        title: currentNode.title,
                        nodeType: currentNode.nodeType,
                        parentId: currentNode.parentId,
                        ownerId: currentNode.ownerId,
                        createdAt: currentNode.createdAt,
                        updatedAt: currentNode.updatedAt,
                        sortOrder: currentNode.sortOrder,
                        isList: currentNode.isList,
                        childrenCount: currentNode.childrenCount,
                        tags: freshNode.tags,  // Only update tags
                        taskData: currentNode.taskData,
                        noteData: currentNode.noteData,
                        templateData: currentNode.templateData,
                        smartFolderData: currentNode.smartFolderData,
                        folderData: currentNode.folderData
                    )
                }

                // Check if changes exist (tags change doesn't count as it's already saved)
                self.checkForChanges()

                logger.log("✅ Tags reloaded: \(freshNode.tags.count) tags", category: "NodeDetailsViewModel")
            }
        } catch {
            logger.log("❌ Failed to reload tags: \(error)", category: "NodeDetailsViewModel", level: .error)
        }
    }

    public func cancel() {
        logger.log("📞 cancel called", category: "NodeDetailsViewModel")
        logger.log("🔄 Reverting all changes to original values", category: "NodeDetailsViewModel")
        
        guard let originalNode = originalNode else { return }
        
        // Reset to original values
        title = originalNode.title
        parentId = originalNode.parentId
        sortOrder = originalNode.sortOrder
        
        // Reset task-specific fields if it's a task
        if originalNode.nodeType == "task", let taskData = originalNode.taskData {
            taskStatus = taskData.status ?? "todo"
            taskPriority = taskData.priority ?? "medium"
            taskDescription = taskData.description ?? ""
            taskArchived = taskData.archived ?? false
            taskDueDate = taskData.dueAt.flatMap { parseISO8601Date($0) }
            taskEarliestStartDate = taskData.earliestStartAt.flatMap { parseISO8601Date($0) }
        }
        
        // Reset note-specific fields if it's a note
        if originalNode.nodeType == "note", let noteData = originalNode.noteData {
            noteBody = noteData.body ?? ""
        }
        
        // Reset template-specific fields if it's a template
        if originalNode.nodeType == "template", let templateData = originalNode.templateData {
            templateDescription = templateData.description ?? ""
            templateCategory = templateData.category ?? ""
            templateUsageCount = templateData.usageCount ?? 0
            templateTargetNodeId = templateData.targetNodeId
            templateCreateContainer = templateData.createContainer ?? true
        }
        
        // Reset smart folder-specific fields if it's a smart folder
        if originalNode.nodeType == "smart_folder", let smartFolderData = originalNode.smartFolderData {
            smartFolderRuleId = smartFolderData.ruleId
            smartFolderAutoRefresh = smartFolderData.autoRefresh ?? true
            smartFolderDescription = smartFolderData.description ?? ""
        }

        // Reset folder-specific fields if it's a folder
        if originalNode.nodeType == "folder", let folderData = originalNode.folderData {
            folderDescription = folderData.description ?? ""
        }
        
        hasChanges = false

        logger.log("✅ All fields reset to original values", category: "NodeDetailsViewModel")
    }

    // MARK: - Task Operations

    public func toggleTaskStatus() async {
        guard let node = node else { return }

        // Route through TreeViewModel if available to ensure smart folder results are updated
        if let treeViewModel = treeViewModel {
            // Use TreeViewModel's toggleTaskStatus which updates smart folder results
            await treeViewModel.toggleTaskStatus(node)

            // Reload the node to get updated state
            await loadNode(nodeId: node.id)
        } else {
            // Fallback to direct DataManager call if no TreeViewModel
            // (This won't update smart folder results, but at least toggles the task)
            guard let dataManager = dataManager else { return }

            if let updatedNode = await dataManager.toggleNodeCompletion(node) {
                await MainActor.run {
                    self.node = updatedNode
                    self.originalNode = updatedNode

                    // Update task status field
                    if let taskData = updatedNode.taskData {
                        self.taskStatus = taskData.status ?? "todo"
                    }
                }
            }
        }
    }
}
