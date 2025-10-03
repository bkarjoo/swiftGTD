import SwiftUI
import Models
import Services
import Core

public struct RuleDesignerView: View {
    @State private var ruleName: String
    @State private var ruleDescription: String
    @State private var ruleLogic: RuleLogic
    @State private var conditions: [RuleCondition]
    @State private var isPublic: Bool
    @State private var showingJSONPreview = false
    @State private var validationErrors: [String] = []
    @State private var showingValidationError = false

    @StateObject private var ruleManager = RuleManager()
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.colorScheme) var colorScheme

    private let rule: Rule?
    private let existingRules: [Rule]
    private let onSave: (Rule) -> Void
    private let onCancel: () -> Void

    public init(
        rule: Rule? = nil,
        existingRules: [Rule] = [],
        onSave: @escaping (Rule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.rule = rule
        self.existingRules = existingRules
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state from existing rule or defaults
        _ruleName = State(initialValue: rule?.name ?? "")
        _ruleDescription = State(initialValue: rule?.description ?? "")
        _ruleLogic = State(initialValue: rule?.ruleData.logic ?? .and)
        _conditions = State(initialValue: rule?.ruleData.conditions ?? [])
        _isPublic = State(initialValue: rule?.isPublic ?? false)
    }

    public var body: some View {
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }

    // MARK: - macOS View

    #if os(macOS)
    private var macOSView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rule == nil ? "Create Rule" : "Edit Rule")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    saveRule()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    basicInfoSection
                    conditionsSection
                    jsonPreviewSection
                }
                .padding()
            }
        }
        .frame(width: 800, height: 600)
        .task {
            // Load data if needed
            if dataManager.nodes.isEmpty {
                await dataManager.syncAllData()
            }
        }
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK") {
                showingValidationError = false
            }
        } message: {
            Text(validationErrors.joined(separator: "\n"))
        }
    }
    #endif

    // MARK: - iOS View

    #if os(iOS)
    private var iOSView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    basicInfoSection
                    conditionsSection
                    jsonPreviewSection
                }
                .padding()
            }
            .navigationTitle(rule == nil ? "Create Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveRule()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .task {
            // Load data if needed
            if dataManager.nodes.isEmpty {
                await dataManager.syncAllData()
            }
        }
        .alert("Validation Error", isPresented: $showingValidationError) {
            Button("OK") {
                showingValidationError = false
            }
        } message: {
            Text(validationErrors.joined(separator: "\n"))
        }
    }
    #endif

    // MARK: - Sections

    private var basicInfoSection: some View {
        GroupBox(label: Label("Basic Information", systemImage: "info.circle")) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rule Name *")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., High Priority Tasks", text: $ruleName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Describe what this rule filters...", text: $ruleDescription)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(isOn: $isPublic) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                        Text("Make this rule public")
                            .font(.system(size: 14))
                        Text("(visible to other users)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var conditionsSection: some View {
        GroupBox(label: Label("Filter Conditions", systemImage: "line.3.horizontal.decrease.circle")) {
            VStack(alignment: .leading, spacing: 12) {
                // Logic selector
                HStack {
                    Text("Match")
                        .font(.system(size: 14, weight: .medium))

                    Picker("", selection: $ruleLogic) {
                        ForEach(RuleLogic.allCases, id: \.self) { logic in
                            Text(logic.displayName).tag(logic)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Spacer()

                    Button(action: addCondition) {
                        Label("Add Condition", systemImage: "plus.circle.fill")
                            .font(.system(size: 13))
                    }
                }

                // Conditions list
                if conditions.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No conditions yet")
                                .foregroundColor(.secondary)
                            Text("Add conditions to define your filter")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(conditions.indices, id: \.self) { index in
                            ConditionRowView(
                                condition: $conditions[index],
                                existingRules: existingRules,
                                onDelete: {
                                    conditions.remove(at: index)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var jsonPreviewSection: some View {
        GroupBox(label:
            HStack {
                Label("JSON Preview", systemImage: "doc.text")
                Spacer()
                Button(showingJSONPreview ? "Hide" : "Show") {
                    withAnimation {
                        showingJSONPreview.toggle()
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
        ) {
            if showingJSONPreview {
                ScrollView {
                    Text(jsonOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                .frame(height: 200)
            }
        }
    }

    // MARK: - Actions

    private func addCondition() {
        // Start with default values so validation doesn't fail immediately
        let newCondition = RuleCondition(
            type: .nodeType,
            operator: .in,
            values: ["task"]  // Default to task type
        )
        conditions.append(newCondition)
    }

    private func saveRule() {
        print("🔵 Saving rule...")
        let ruleData = RuleData(logic: ruleLogic, conditions: conditions)

        // Validate
        validationErrors = ruleManager.validateRuleData(ruleData)
        if !validationErrors.isEmpty {
            print("❌ Validation errors: \(validationErrors)")
            showingValidationError = true
            return
        }

        let newRule = Rule(
            id: rule?.id ?? UUID().uuidString,
            name: ruleName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: ruleDescription.isEmpty ? nil : ruleDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            ruleData: ruleData,
            isPublic: isPublic,
            isSystem: rule?.isSystem ?? false,
            ownerId: rule?.ownerId,
            createdAt: rule?.createdAt,
            updatedAt: rule?.updatedAt
        )

        print("✅ Calling onSave with rule: \(newRule.name)")
        onSave(newRule)
    }

    private var canSave: Bool {
        !ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var jsonOutput: String {
        let ruleData = RuleData(logic: ruleLogic, conditions: conditions)
        let rule = Rule(
            name: ruleName.isEmpty ? "Untitled Rule" : ruleName,
            description: ruleDescription.isEmpty ? nil : ruleDescription,
            ruleData: ruleData,
            isPublic: isPublic
        )

        if let jsonData = try? JSONEncoder().encode(rule),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Pretty print
            if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                return prettyString
            }
            return jsonString
        }
        return "{}"
    }
}

// MARK: - Condition Row View

struct ConditionRowView: View {
    @Binding var condition: RuleCondition
    let existingRules: [Rule]
    let onDelete: () -> Void

    @EnvironmentObject private var dataManager: DataManager
    @State private var selectedTags: [Tag] = []
    @State private var selectedNode: Node?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            // Field selector
            Picker("", selection: $condition.type) {
                ForEach(ConditionType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .frame(width: 140)
            .onChange(of: condition.type) { newType in
                // Reset operator when type changes
                if let firstOp = newType.availableOperators.first {
                    condition.operator = firstOp
                }
                // Clear values
                condition.values = []
            }

            // Operator selector
            Picker("", selection: $condition.operator) {
                ForEach(condition.type.availableOperators, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 180)
            .disabled(condition.type.availableOperators.count <= 1)

            // Value input (if needed)
            if !condition.operator.requiresNoValues {
                valueInput
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var valueInput: some View {
        switch condition.type.valueType {
        case .multiSelect:
            MultiSelectPicker(
                selectedValues: $condition.values,
                options: condition.type.valueOptions
            )
            .frame(maxWidth: 200)

        case .text:
            TextField("Enter text...", text: Binding(
                get: { condition.values.first ?? "" },
                set: { condition.values = [$0] }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)

        case .boolean:
            Picker("", selection: Binding(
                get: { condition.values.first ?? "true" },
                set: { condition.values = [$0] }
            )) {
                Text("Yes").tag("true")
                Text("No").tag("false")
            }
            .pickerStyle(.segmented)
            .frame(width: 100)

        case .date:
            if condition.operator.requiresNumberInput {
                HStack {
                    TextField("Days", text: Binding(
                        get: { condition.values.first ?? "" },
                        set: { condition.values = [$0] }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                    Text("days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if condition.operator == .between {
                HStack {
                    DatePicker("", selection: Binding(
                        get: { dateFromString(condition.values.first ?? "") },
                        set: { condition.values[0] = dateToString($0) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()

                    Text("to")
                        .font(.caption)

                    DatePicker("", selection: Binding(
                        get: { dateFromString(condition.values.count > 1 ? condition.values[1] : "") },
                        set: {
                            if condition.values.count > 1 {
                                condition.values[1] = dateToString($0)
                            } else {
                                condition.values.append(dateToString($0))
                            }
                        }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            } else {
                DatePicker("", selection: Binding(
                    get: { dateFromString(condition.values.first ?? "") },
                    set: { condition.values = [dateToString($0)] }
                ), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
            }

        case .tags:
            TagMultiSelector(
                selectedTagIds: $condition.values
            )
            .frame(maxWidth: 200)

        case .node:
            NodeSelector(
                selectedNodeId: Binding(
                    get: { condition.values.first },
                    set: { condition.values = $0 != nil ? [$0!] : [] }
                ),
                nodeType: condition.type == .parentAncestor ? "folder" : nil
            )
            .frame(maxWidth: 200)

        case .rule:
            Picker("Select rule...", selection: Binding(
                get: { condition.values.first ?? "" },
                set: { condition.values = [$0] }
            )) {
                Text("Select rule...").tag("")
                ForEach(existingRules.filter { !$0.isSystem }, id: \.id) { rule in
                    Text(rule.name).tag(rule.id)
                }
            }
            .frame(maxWidth: 200)
        }
    }

    private func dateFromString(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string) ?? Date()
    }

    private func dateToString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

// MARK: - Multi Select Picker

struct MultiSelectPicker: View {
    @Binding var selectedValues: [String]
    let options: [ValueOption]
    @State private var showingPopover = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            HStack {
                if selectedValues.isEmpty {
                    Text("Select...")
                        .foregroundColor(.secondary)
                } else {
                    Text(selectedLabels)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
        .popover(isPresented: $showingPopover) {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button(action: {
                        if selectedValues.contains(option.value) {
                            selectedValues.removeAll { $0 == option.value }
                        } else {
                            selectedValues.append(option.value)
                        }
                    }) {
                        HStack {
                            Image(systemName: selectedValues.contains(option.value) ? "checkmark.square" : "square")
                                .foregroundColor(.blue)
                            Text(option.label)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .frame(width: 200)
            .padding(.vertical, 4)
        }
    }

    private var selectedLabels: String {
        options
            .filter { selectedValues.contains($0.value) }
            .map { $0.label }
            .joined(separator: ", ")
    }
}

// MARK: - Placeholder Components

// Tag selector component
struct TagMultiSelector: View {
    @Binding var selectedTagIds: [String]
    @EnvironmentObject private var dataManager: DataManager
    @State private var showingPopover = false
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme

    private var availableTags: [Tag] {
        let tags = dataManager.tags

        if searchText.isEmpty {
            return tags.sorted { $0.name < $1.name }
        }

        return tags.filter { tag in
            tag.name.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.name < $1.name }
    }

    private var selectedTags: [Tag] {
        dataManager.tags.filter { selectedTagIds.contains($0.id) }
    }

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            HStack {
                if selectedTags.isEmpty {
                    Text("Select tags...")
                        .foregroundColor(.secondary)
                } else {
                    Text(selectedTags.map { $0.name }.joined(separator: ", "))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
        .popover(isPresented: $showingPopover) {
            VStack(spacing: 0) {
                // Header with selected count
                HStack {
                    Text("\(selectedTagIds.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !selectedTagIds.isEmpty {
                        Button("Clear all") {
                            selectedTagIds.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search tags...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(8)
                .background(Color.gray.opacity(0.05))

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        if availableTags.isEmpty {
                            Text(dataManager.tags.isEmpty ? "No tags available" : "No tags found")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding()
                        } else {
                            ForEach(availableTags, id: \.id) { tag in
                                let isSelected = selectedTagIds.contains(tag.id)
                                Button(action: {
                                    if isSelected {
                                        selectedTagIds.removeAll { $0 == tag.id }
                                    } else {
                                        selectedTagIds.append(tag.id)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: isSelected ? "checkmark.square" : "square")
                                            .foregroundColor(.blue)
                                            .font(.caption)

                                        Text(tag.name)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        if let color = tag.color {
                                            Circle()
                                                .fill(Color(hex: color))
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                if tag.id != availableTags.last?.id {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
                .frame(width: 250)
                .frame(maxHeight: 300)
            }
            .padding(.vertical, 4)
        }
    }
}

struct NodeSelector: View {
    @Binding var selectedNodeId: String?
    let nodeType: String?
    @EnvironmentObject private var dataManager: DataManager
    @State private var searchText = ""
    @State private var showingPopover = false
    @Environment(\.colorScheme) var colorScheme

    private var availableNodes: [Node] {
        let nodes = dataManager.nodes.filter { node in
            if let nodeType = nodeType {
                return node.nodeType == nodeType
            }
            // Default to folders and smart folders
            return node.nodeType == "folder" || node.nodeType == "smart_folder"
        }

        if searchText.isEmpty {
            return nodes.sorted { $0.title < $1.title }
        }

        return nodes.filter { node in
            node.title.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.title < $1.title }
    }

    private var selectedNode: Node? {
        guard let selectedId = selectedNodeId else { return nil }
        return dataManager.nodes.first { $0.id == selectedId }
    }

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            HStack {
                if let selected = selectedNode {
                    Image(systemName: selected.nodeType == "smart_folder" ? "magnifyingglass.circle" : "folder")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(selected.title)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                } else {
                    Text("Select folder...")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
        .popover(isPresented: $showingPopover) {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search folders...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(8)
                .background(Color.gray.opacity(0.05))

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        // Clear selection option
                        Button(action: {
                            selectedNodeId = nil
                            showingPopover = false
                            searchText = ""
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.secondary)
                                Text("Clear selection")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        // Node list
                        if availableNodes.isEmpty {
                            Text("No folders found")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .padding()
                        } else {
                            ForEach(availableNodes, id: \.id) { node in
                                Button(action: {
                                    selectedNodeId = node.id
                                    showingPopover = false
                                    searchText = ""
                                }) {
                                    HStack {
                                        Image(systemName: node.nodeType == "smart_folder" ? "magnifyingglass.circle" : "folder")
                                            .foregroundColor(node.id == selectedNodeId ? .white : .blue)
                                            .font(.caption)
                                        Text(node.title)
                                            .foregroundColor(node.id == selectedNodeId ? .white : .primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if node.id == selectedNodeId {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.white)
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(node.id == selectedNodeId ? Color.blue : Color.clear)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(width: 250)
                .frame(maxHeight: 300)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RuleDesignerView_Previews: PreviewProvider {
    static var previews: some View {
        RuleDesignerView(
            onSave: { _ in },
            onCancel: { }
        )
        .environmentObject(DataManager())
    }
}
#endif