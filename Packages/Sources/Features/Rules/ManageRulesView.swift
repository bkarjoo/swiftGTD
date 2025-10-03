import SwiftUI
import Models
import Services
import Core

public struct ManageRulesView: View {
    @StateObject private var ruleManager = RuleManager()
    @State private var showingCreateRule = false
    @State private var editingRule: Rule?
    @State private var deletingRule: Rule?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Search bar
            searchBar

            // Rules list
            if ruleManager.isLoading {
                Spacer()
                ProgressView("Loading rules...")
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else if filteredRules.isEmpty {
                emptyStateView
            } else {
                rulesList
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .navigationTitle("Manage Rules")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(isPresented: $showingCreateRule) {
            RuleDesignerView(
                rule: nil,
                onSave: { rule in
                    Task { @MainActor in
                        do {
                            try await ruleManager.createRule(
                                name: rule.name,
                                description: rule.description,
                                ruleData: rule.ruleData,
                                isPublic: rule.isPublic
                            )
                            showingCreateRule = false
                        } catch {
                            errorMessage = "Failed to create rule: \(error.localizedDescription)"
                            print("❌ Failed to create rule: \(error)")
                        }
                    }
                },
                onCancel: {
                    showingCreateRule = false
                }
            )
        }
        .sheet(item: $editingRule) { rule in
            RuleDesignerView(
                rule: rule,
                existingRules: ruleManager.rules,
                onSave: { updatedRule in
                    Task { @MainActor in
                        do {
                            try await ruleManager.updateRule(
                                id: rule.id,
                                name: updatedRule.name,
                                description: updatedRule.description,
                                ruleData: updatedRule.ruleData,
                                isPublic: updatedRule.isPublic
                            )
                            editingRule = nil
                        } catch {
                            errorMessage = "Failed to update rule: \(error.localizedDescription)"
                            print("❌ Failed to update rule: \(error)")
                        }
                    }
                },
                onCancel: {
                    editingRule = nil
                }
            )
        }
        .alert("Delete Rule", isPresented: .constant(deletingRule != nil)) {
            Button("Cancel", role: .cancel) {
                deletingRule = nil
            }
            Button("Delete", role: .destructive) {
                if let rule = deletingRule {
                    Task {
                        do {
                            try await ruleManager.deleteRule(id: rule.id)
                            deletingRule = nil
                        } catch {
                            errorMessage = "Failed to delete rule: \(error.localizedDescription)"
                            deletingRule = nil
                        }
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete the rule \"\(deletingRule?.name ?? "")\"? This cannot be undone.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await ruleManager.loadRules()
        }
    }

    private var filteredRules: [Rule] {
        if searchText.isEmpty {
            return ruleManager.rules
        }
        return ruleManager.rules.filter { rule in
            rule.name.localizedCaseInsensitiveContains(searchText) ||
            (rule.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var headerView: some View {
        HStack {
            Text("\(ruleManager.rules.count) Rules")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                showingCreateRule = true
            }) {
                Label("Create Rule", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search rules...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            if searchText.isEmpty {
                Text("No Rules Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Create your first rule to filter nodes dynamically")
                    .foregroundColor(.secondary)
            } else {
                Text("No Rules Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("No rules match your search")
                    .foregroundColor(.secondary)
            }

            Button(action: {
                if !searchText.isEmpty {
                    searchText = ""
                } else {
                    showingCreateRule = true
                }
            }) {
                Label(searchText.isEmpty ? "Create Your First Rule" : "Clear Search",
                      systemImage: searchText.isEmpty ? "plus.circle.fill" : "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredRules) { rule in
                    RuleRowView(
                        rule: rule,
                        onEdit: {
                            editingRule = rule
                        },
                        onDelete: {
                            deletingRule = rule
                        },
                        onDuplicate: {
                            Task {
                                do {
                                    try await ruleManager.duplicateRule(
                                        id: rule.id,
                                        newName: "\(rule.name) (Copy)"
                                    )
                                } catch {
                                    errorMessage = "Failed to duplicate rule: \(error.localizedDescription)"
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Rule Row View

struct RuleRowView: View {
    let rule: Rule
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme

    private var backgroundColor: Color {
        if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: rule.isSystem ? "lock.doc" : (rule.isPublic ? "globe" : "doc.text"))
                .font(.system(size: 20))
                .foregroundColor(rule.isSystem ? .orange : (rule.isPublic ? .blue : .secondary))
                .frame(width: 30)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                if let description = rule.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    if rule.isSystem {
                        Label("System", systemImage: "lock")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if rule.isPublic {
                        Label("Public", systemImage: "globe")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    Text("\(rule.ruleData.conditions.count) conditions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if !rule.isSystem {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .help("Edit Rule")
                }

                Button(action: onDuplicate) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.green)
                .help("Duplicate Rule")

                if !rule.isSystem {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .help("Delete Rule")
                }
            }
            .opacity(isHovered ? 1 : 0.3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ManageRulesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ManageRulesView()
        }
    }
}
#endif