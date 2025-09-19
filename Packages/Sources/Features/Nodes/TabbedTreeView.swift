#if os(macOS)
import SwiftUI
import Combine
import Core
import Models
import Services

@MainActor
public class TabModel: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public var title: String
    public let viewModel: TreeViewModel

    public init(title: String = "All Nodes") {
        self.title = title
        self.viewModel = TreeViewModel()
    }
}

public struct TabbedTreeView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var tabs: [TabModel] = [TabModel()]
    @State private var selectedTabId: UUID?
    @State private var activeCreateVM: TreeViewModel?

    public init() {}

    private var currentTab: TabModel? {
        tabs.first { $0.id == selectedTabId }
    }

    public var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(currentTab?.viewModel.currentFocusedNode?.title ?? "All Nodes")
                .toolbar {
                    toolbarContent
                }
                .sheet(item: $activeCreateVM) { viewModel in
                    CreateNodeSheet(viewModel: viewModel)
                        .environmentObject(dataManager)
                        .frame(minWidth: 400, minHeight: 150)
                }
        }
        .onAppear {
            if selectedTabId == nil, let firstTab = tabs.first {
                selectedTabId = firstTab.id
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            TabBarView(
                tabs: $tabs,
                selectedTabId: $selectedTabId,
                onNewTab: { addNewTab() },
                onCloseTab: { closeTab($0) }
            )
            .frame(height: 36)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            tabContent
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if let currentTab = currentTab {
            TreeView_macOS(viewModel: currentTab.viewModel)
                .environmentObject(dataManager)
                .environment(\.isInTabbedView, true)
                .onChange(of: currentTab.viewModel.focusedNodeId) { _ in
                    updateTabTitle(currentTab)
                }
                .id(currentTab.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let currentTab = currentTab {
            ToolbarItem(placement: .cancellationAction) {
                HStack(spacing: 8) {
                    NetworkStatusIndicator(lastSyncDate: dataManager.lastSyncDate)

                    Button(action: {
                        Task {
                            await currentTab.viewModel.refreshNodes()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }

                Menu {
                    Button("Folder") {
                        currentTab.viewModel.createNodeType = "folder"
                        currentTab.viewModel.createNodeTitle = ""
                        activeCreateVM = currentTab.viewModel
                    }
                    Button("Task") {
                        currentTab.viewModel.createNodeType = "task"
                        currentTab.viewModel.createNodeTitle = ""
                        activeCreateVM = currentTab.viewModel
                    }
                    Button("Note") {
                        currentTab.viewModel.createNodeType = "note"
                        currentTab.viewModel.createNodeTitle = ""
                        activeCreateVM = currentTab.viewModel
                    }
                    Button("Template") {
                        currentTab.viewModel.createNodeType = "template"
                        currentTab.viewModel.createNodeTitle = ""
                        activeCreateVM = currentTab.viewModel
                    }
                    Button("Smart Folder") {
                        currentTab.viewModel.createNodeType = "smart_folder"
                        currentTab.viewModel.createNodeTitle = ""
                        activeCreateVM = currentTab.viewModel
                    }
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
            }
        }
    }

    private func addNewTab() {
        let newTab = TabModel(title: "New Tab")
        tabs.append(newTab)
        selectedTabId = newTab.id
    }

    private func closeTab(_ tabId: UUID) {
        guard tabs.count > 1 else { return }

        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            let wasSelected = selectedTabId == tabId
            tabs.remove(at: index)

            if wasSelected {
                if index < tabs.count {
                    selectedTabId = tabs[index].id
                } else if index > 0 {
                    selectedTabId = tabs[index - 1].id
                } else if let firstTab = tabs.first {
                    selectedTabId = firstTab.id
                }
            }
        }
    }

    private func updateTabTitle(_ tab: TabModel) {
        if let focusedId = tab.viewModel.focusedNodeId,
           let node = tab.viewModel.allNodes.first(where: { $0.id == focusedId }) {
            tab.title = String(node.title.prefix(20))
        } else {
            tab.title = "All Nodes"
        }
    }
}

struct TabBarView: View {
    @Binding var tabs: [TabModel]
    @Binding var selectedTabId: UUID?
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabs) { tab in
                        TabBarItem(
                            tab: tab,
                            isSelected: tab.id == selectedTabId,
                            onSelect: { selectedTabId = tab.id },
                            onClose: { onCloseTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .padding(.horizontal, 4)
        }
    }
}

struct TabBarItem: View {
    @ObservedObject var tab: TabModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            if tab.viewModel.focusedNodeId != nil {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)

            if isSelected || isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color(NSColor.controlAccentColor).opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color(NSColor.controlAccentColor).opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#endif