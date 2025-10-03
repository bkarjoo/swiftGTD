import Foundation
import Networking
import Models
import Core
import SwiftUI

private let logger = Logger.shared

/// Manages rule operations and state
@MainActor
public class RuleManager: ObservableObject {
    @Published public var rules: [Rule] = []
    @Published public var isLoading = false
    @Published public var error: String?

    private let apiClient = APIClient.shared

    public init() {}

    // MARK: - Public Methods

    /// Load all rules
    public func loadRules(includePublic: Bool = true, includeSystem: Bool = true) async {
        isLoading = true
        error = nil

        do {
            let response = try await apiClient.getRules(
                includePublic: includePublic,
                includeSystem: includeSystem
            )
            rules = response.rules.sorted { $0.name < $1.name }
            logger.log("📋 Loaded \(rules.count) rules", category: "RuleManager")
        } catch {
            self.error = "Failed to load rules: \(error.localizedDescription)"
            logger.log("❌ Failed to load rules: \(error)", category: "RuleManager", level: .error)
        }

        isLoading = false
    }

    /// Get a specific rule by ID
    public func getRule(id: String) async throws -> Rule {
        return try await apiClient.getRule(id: id)
    }

    /// Create a new rule
    @discardableResult
    public func createRule(name: String, description: String?, ruleData: RuleData, isPublic: Bool) async throws -> Rule {
        let request = RuleCreateRequest(
            name: name,
            description: description,
            ruleData: ruleData,
            isPublic: isPublic
        )

        let newRule = try await apiClient.createRule(request)

        // Add to local state
        rules.append(newRule)
        rules.sort { $0.name < $1.name }

        logger.log("✅ Created rule: \(newRule.name)", category: "RuleManager")
        return newRule
    }

    /// Update an existing rule
    @discardableResult
    public func updateRule(id: String, name: String? = nil, description: String? = nil, ruleData: RuleData? = nil, isPublic: Bool? = nil) async throws -> Rule {
        let request = RuleUpdateRequest(
            name: name,
            description: description,
            ruleData: ruleData,
            isPublic: isPublic
        )

        let updatedRule = try await apiClient.updateRule(id: id, request: request)

        // Update local state
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index] = updatedRule
        }

        logger.log("✅ Updated rule: \(updatedRule.name)", category: "RuleManager")
        return updatedRule
    }

    /// Delete a rule
    public func deleteRule(id: String) async throws {
        try await apiClient.deleteRule(id: id)

        // Remove from local state
        rules.removeAll { $0.id == id }

        logger.log("✅ Deleted rule: \(id)", category: "RuleManager")
    }

    /// Duplicate a rule
    @discardableResult
    public func duplicateRule(id: String, newName: String? = nil) async throws -> Rule {
        let duplicatedRule = try await apiClient.duplicateRule(id: id, newName: newName)

        // Add to local state
        rules.append(duplicatedRule)
        rules.sort { $0.name < $1.name }

        logger.log("✅ Duplicated rule: \(duplicatedRule.name)", category: "RuleManager")
        return duplicatedRule
    }

    /// Validate rule data structure
    public func validateRuleData(_ ruleData: RuleData) -> [String] {
        var errors: [String] = []

        // Check logic value
        if ruleData.logic != .and && ruleData.logic != .or {
            errors.append("Logic must be AND or OR")
        }

        // Empty conditions are allowed (matches no items)
        if ruleData.conditions.isEmpty {
            return errors
        }

        // Validate each condition
        for (index, condition) in ruleData.conditions.enumerated() {
            let conditionNumber = index + 1

            // Check operator is valid for condition type
            let availableOperators = condition.type.availableOperators
            if !availableOperators.contains(condition.operator) {
                errors.append("Condition \(conditionNumber): Invalid operator '\(condition.operator.rawValue)' for type '\(condition.type.rawValue)'")
            }

            // Check values are provided when needed
            if !condition.operator.requiresNoValues && condition.values.isEmpty {
                errors.append("Condition \(conditionNumber): Values required for operator '\(condition.operator.rawValue)'")
            }

            // Validate specific value formats
            switch condition.type {
            case .dueDate, .earliestStart:
                if condition.operator.requiresNumberInput {
                    // Check that value is a valid number
                    if let value = condition.values.first, Int(value) == nil {
                        errors.append("Condition \(conditionNumber): Days value must be a number")
                    }
                } else if !condition.operator.requiresNoValues && condition.operator != .between {
                    // Check date format
                    if let value = condition.values.first {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withFullDate]
                        if formatter.date(from: value) == nil {
                            errors.append("Condition \(conditionNumber): Date must be in YYYY-MM-DD format")
                        }
                    }
                }
                // For between operator, check second date
                if condition.operator == .between && condition.values.count >= 2 {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    if formatter.date(from: condition.values[1]) == nil {
                        errors.append("Condition \(conditionNumber): Second date must be in YYYY-MM-DD format")
                    }
                }

            case .tagContains, .savedFilter:
                // Check for valid UUIDs
                for value in condition.values {
                    if UUID(uuidString: value) == nil {
                        errors.append("Condition \(conditionNumber): Invalid UUID format")
                        break
                    }
                }

            default:
                break
            }
        }

        return errors
    }
}