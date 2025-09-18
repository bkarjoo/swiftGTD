import SwiftUI
import Core
import Models
import Services

public struct CreateNodeView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var title = ""
    @State private var content = ""
    @State private var selectedType: NodeType = .task
    
    public init() {}
    @State private var selectedTags: Set<Tag> = []
    @State private var dueDate: Date?
    @State private var showDatePicker = false
    
    public var body: some View {
        NavigationView {
            Form {
                Section("Basic Information") {
                    TextField("Title", text: $title)
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach(NodeType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if content.isEmpty {
                                    Text("Description (optional)")
                                        .foregroundColor(.gray.opacity(0.5))
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                
                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $showDatePicker)
                    
                    if showDatePicker {
                        DatePicker(
                            "Due Date",
                            selection: Binding(
                                get: { dueDate ?? Date() },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
                
                Section("Tags") {
                    if dataManager.tags.isEmpty {
                        Text("No tags available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(dataManager.tags) { tag in
                            HStack {
                                TagChip(tag: tag)
                                Spacer()
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New \(selectedType.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        Task {
                            await dataManager.createNode(
                                title: title,
                                type: selectedType.rawValue,
                                content: content.isEmpty ? nil : content,
                                parentId: nil,
                                tags: Array(selectedTags)
                            )
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

#Preview {
    CreateNodeView()
        .environmentObject(DataManager())
}