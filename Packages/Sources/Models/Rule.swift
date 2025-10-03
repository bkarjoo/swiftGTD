import Foundation

// MARK: - Rule Models

/// Rule model - Represents a standalone, composable filtering rule
public struct Rule: Codable, Identifiable {
    public let id: String
    public var name: String
    public var description: String?
    public var ruleData: RuleData
    public var isPublic: Bool
    public let isSystem: Bool
    public let ownerId: String?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        ruleData: RuleData,
        isPublic: Bool = false,
        isSystem: Bool = false,
        ownerId: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.ruleData = ruleData
        self.isPublic = isPublic
        self.isSystem = isSystem
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ruleData = "rule_data"
        case isPublic = "is_public"
        case isSystem = "is_system"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The root structure of a rule
public struct RuleData: Codable {
    public var logic: RuleLogic
    public var conditions: [RuleCondition]

    public init(logic: RuleLogic = .and, conditions: [RuleCondition] = []) {
        self.logic = logic
        self.conditions = conditions
    }
}

/// Logical operator for combining conditions
public enum RuleLogic: String, Codable, CaseIterable {
    case and = "AND"
    case or = "OR"

    public var displayName: String {
        switch self {
        case .and: return "ALL conditions"
        case .or: return "ANY condition"
        }
    }
}

/// A single condition in a rule
public struct RuleCondition: Codable, Identifiable {
    public let id = UUID()
    public var type: ConditionType
    public var `operator`: ConditionOperator
    public var values: [String]

    enum CodingKeys: String, CodingKey {
        case type
        case `operator`
        case values
    }

    public init(type: ConditionType, operator: ConditionOperator, values: [String] = []) {
        self.type = type
        self.`operator` = `operator`
        self.values = values
    }
}

/// Types of conditions available
public enum ConditionType: String, Codable, CaseIterable {
    case nodeType = "node_type"
    case tagContains = "tag_contains"
    case parentNode = "parent_node"
    case parentAncestor = "parent_ancestor"
    case taskStatus = "task_status"
    case taskPriority = "task_priority"
    case titleContains = "title_contains"
    case hasChildren = "has_children"
    case dueDate = "due_date"
    case earliestStart = "earliest_start"
    case savedFilter = "saved_filter"

    public var displayName: String {
        switch self {
        case .nodeType: return "Node Type"
        case .tagContains: return "Tags"
        case .parentNode: return "Parent Folder"
        case .parentAncestor: return "Parent Ancestor"
        case .taskStatus: return "Task Status"
        case .taskPriority: return "Task Priority"
        case .titleContains: return "Title Contains"
        case .hasChildren: return "Has Children"
        case .dueDate: return "Due Date"
        case .earliestStart: return "Start Date"
        case .savedFilter: return "Existing Rule"
        }
    }

    public var valueType: ValueType {
        switch self {
        case .nodeType: return .multiSelect
        case .tagContains: return .tags
        case .parentNode: return .node
        case .parentAncestor: return .node
        case .taskStatus: return .multiSelect
        case .taskPriority: return .multiSelect
        case .titleContains: return .text
        case .hasChildren: return .boolean
        case .dueDate: return .date
        case .earliestStart: return .date
        case .savedFilter: return .rule
        }
    }

    public enum ValueType {
        case multiSelect
        case tags
        case node
        case text
        case boolean
        case date
        case rule
    }
}

/// Operators for different condition types
public enum ConditionOperator: String, Codable {
    // Common operators
    case equals = "equals"
    case notEquals = "not_equals"
    case `in` = "in"
    case notIn = "not_in"

    // Text operators
    case contains = "contains"
    case notContains = "not_contains"

    // Tag operators
    case any = "any"
    case all = "all"
    case none = "none"

    // Date operators
    case before = "before"
    case after = "after"
    case on = "on"
    case between = "between"
    case isNull = "is_null"
    case isNotNull = "is_not_null"
    case isToday = "is_today"
    case isOverdue = "is_overdue"
    case thisWeek = "this_week"
    case nextWeek = "next_week"
    case thisMonth = "this_month"
    case yesterday = "yesterday"
    case tomorrow = "tomorrow"

    // Relative date operators
    case overdueByDays = "overdue_by_days"
    case overdueByMoreThan = "overdue_by_more_than"
    case overdueByLessThan = "overdue_by_less_than"
    case dueInDays = "due_in_days"
    case dueWithinDays = "due_within_days"
    case dueInMoreThanDays = "due_in_more_than_days"
    case withinLastDays = "within_last_days"
    case moreThanDaysAgo = "more_than_days_ago"
    case exactlyDaysAgo = "exactly_days_ago"
    case withinNextDays = "within_next_days"
    case startsWithinDays = "starts_within_days"
    case startsInMoreThanDays = "starts_in_more_than_days"

    public var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .in: return "is one of"
        case .notIn: return "is not one of"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .any: return "has any of"
        case .all: return "has all of"
        case .none: return "has none of"
        case .before: return "is before"
        case .after: return "is after"
        case .on: return "is on"
        case .between: return "is between"
        case .isNull: return "is not set"
        case .isNotNull: return "is set"
        case .isToday: return "is today"
        case .isOverdue: return "is overdue"
        case .thisWeek: return "this week"
        case .nextWeek: return "next week"
        case .thisMonth: return "this month"
        case .yesterday: return "yesterday"
        case .tomorrow: return "tomorrow"
        case .overdueByDays: return "overdue by X days"
        case .overdueByMoreThan: return "overdue by more than X days"
        case .overdueByLessThan: return "overdue by less than X days"
        case .dueInDays: return "due in X days"
        case .dueWithinDays: return "due within X days"
        case .dueInMoreThanDays: return "due in more than X days"
        case .withinLastDays: return "within last X days"
        case .moreThanDaysAgo: return "more than X days ago"
        case .exactlyDaysAgo: return "exactly X days ago"
        case .withinNextDays: return "within next X days"
        case .startsWithinDays: return "starts within X days"
        case .startsInMoreThanDays: return "starts in more than X days"
        }
    }

    /// Whether this operator requires no values
    public var requiresNoValues: Bool {
        switch self {
        case .isNull, .isNotNull, .isToday, .isOverdue,
             .thisWeek, .nextWeek, .thisMonth, .yesterday, .tomorrow:
            return true
        default:
            return false
        }
    }

    /// Whether this operator requires a number input (days)
    public var requiresNumberInput: Bool {
        switch self {
        case .overdueByDays, .overdueByMoreThan, .overdueByLessThan,
             .dueInDays, .dueWithinDays, .dueInMoreThanDays,
             .withinLastDays, .moreThanDaysAgo, .exactlyDaysAgo,
             .withinNextDays, .startsWithinDays, .startsInMoreThanDays:
            return true
        default:
            return false
        }
    }
}

// MARK: - Operator Groups

public extension ConditionType {
    /// Available operators for this condition type
    var availableOperators: [ConditionOperator] {
        switch self {
        case .nodeType:
            return [.in, .notIn]
        case .tagContains:
            return [.any, .all, .none]
        case .parentNode:
            return [.equals, .notEquals, .isNull, .isNotNull]
        case .parentAncestor:
            return [.equals, .notEquals]
        case .taskStatus:
            return [.in, .notIn]
        case .taskPriority:
            return [.in, .notIn]
        case .titleContains:
            return [.contains, .notContains, .equals, .notEquals]
        case .hasChildren:
            return [.equals]
        case .dueDate:
            return [
                .isOverdue, .overdueByDays, .overdueByMoreThan, .overdueByLessThan,
                .dueInDays, .dueWithinDays, .dueInMoreThanDays,
                .withinLastDays, .moreThanDaysAgo, .exactlyDaysAgo, .withinNextDays,
                .thisWeek, .nextWeek, .thisMonth, .yesterday, .tomorrow, .isToday,
                .before, .after, .on, .between, .isNull, .isNotNull
            ]
        case .earliestStart:
            return [
                .startsWithinDays, .startsInMoreThanDays,
                .withinLastDays, .moreThanDaysAgo, .exactlyDaysAgo, .withinNextDays,
                .thisWeek, .nextWeek, .thisMonth, .yesterday, .tomorrow, .isToday,
                .before, .after, .on, .between, .isNull, .isNotNull
            ]
        case .savedFilter:
            return [.equals]
        }
    }
}

// MARK: - Value Options

public struct ValueOption: Identifiable {
    public let id: String
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.id = value
        self.value = value
        self.label = label
    }
}

public extension ConditionType {
    /// Available value options for multi-select types
    var valueOptions: [ValueOption] {
        switch self {
        case .nodeType:
            return [
                ValueOption(value: "task", label: "Task"),
                ValueOption(value: "note", label: "Note"),
                ValueOption(value: "folder", label: "Folder"),
                ValueOption(value: "template", label: "Template"),
                ValueOption(value: "smart_folder", label: "Smart Folder")
            ]
        case .taskStatus:
            return [
                ValueOption(value: "todo", label: "To Do"),
                ValueOption(value: "in_progress", label: "In Progress"),
                ValueOption(value: "done", label: "Done"),
                ValueOption(value: "dropped", label: "Dropped")
            ]
        case .taskPriority:
            return [
                ValueOption(value: "low", label: "Low"),
                ValueOption(value: "medium", label: "Medium"),
                ValueOption(value: "high", label: "High")
            ]
        case .hasChildren:
            return [
                ValueOption(value: "true", label: "Yes"),
                ValueOption(value: "false", label: "No")
            ]
        default:
            return []
        }
    }
}

// MARK: - API Request/Response Types

public struct RuleCreateRequest: Codable {
    public let name: String
    public let description: String?
    public let ruleData: RuleData
    public let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case ruleData = "rule_data"
        case isPublic = "is_public"
    }

    public init(name: String, description: String? = nil, ruleData: RuleData, isPublic: Bool = false) {
        self.name = name
        self.description = description
        self.ruleData = ruleData
        self.isPublic = isPublic
    }
}

public struct RuleUpdateRequest: Codable {
    public let name: String?
    public let description: String?
    public let ruleData: RuleData?
    public let isPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case ruleData = "rule_data"
        case isPublic = "is_public"
    }

    public init(name: String? = nil, description: String? = nil, ruleData: RuleData? = nil, isPublic: Bool? = nil) {
        self.name = name
        self.description = description
        self.ruleData = ruleData
        self.isPublic = isPublic
    }
}

/// Response containing a list of rules
public struct RuleListResponse: Codable {
    public let rules: [Rule]
    public let total: Int

    public init(rules: [Rule], total: Int) {
        self.rules = rules
        self.total = total
    }
}