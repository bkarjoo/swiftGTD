#if os(macOS)
import SwiftUI
import Combine
import Core
import Models
import Services

@MainActor
public class TabModel: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var title: String {
        didSet {
            // Notify TabbedTreeView to save state when title changes
            NotificationCenter.default.post(name: .tabStateChanged, object: nil)
        }
    }
    public let viewModel: TreeViewModel
    private var cancellables = Set<AnyCancellable>()

    public init(id: UUID = UUID(), title: String = "All Nodes", focusedNodeId: String? = nil) {
        self.id = id
        self.title = title
        self.viewModel = TreeViewModel()
        self.viewModel.focusedNodeId = focusedNodeId

        // Watch for focus changes and notify
        self.viewModel.$focusedNodeId
            .sink { _ in
                NotificationCenter.default.post(name: .tabStateChanged, object: nil)
            }
            .store(in: &cancellables)
    }
}

extension Notification.Name {
    static let tabStateChanged = Notification.Name("tabStateChanged")
    static let focusChanged = Notification.Name("focusChanged")
}

public struct TabbedTreeView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.scenePhase) var scenePhase
    @State private var tabs: [TabModel] = []
    @State private var selectedTabId: UUID?
    @State private var activeCreateVM: TreeViewModel?
    @State private var showingNewTabDialog = false
    @State private var newTabName = ""
    @State private var editingTabId: UUID?
    @State private var keyEventMonitor: Any?
    @State private var hasRestoredState = false
    @State private var notificationObservers: [NSObjectProtocol] = []
    @State private var focusSubscriptions: [UUID: AnyCancellable] = [:]
    private let stateManager = UIStateManager.shared
    private let logger = Logger.shared

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
                .sheet(isPresented: $showingNewTabDialog) {
                    NewTabSheet(tabName: $newTabName) {
                        createTabWithName(newTabName)
                        showingNewTabDialog = false
                    }
                }
        }
        .onAppear {
            if !hasRestoredState {
                restoreState()
                hasRestoredState = true
            }
            setupKeyEventMonitor()
            setupStateChangeObservers()
            setupFocusSubscriptions()
        }
        .onDisappear {
            if let monitor = keyEventMonitor {
                NSEvent.removeMonitor(monitor)
                keyEventMonitor = nil
            }
            // Remove all notification observers
            for observer in notificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            notificationObservers.removeAll()
            // Cancel focus subscriptions
            focusSubscriptions.values.forEach { $0.cancel() }
            focusSubscriptions.removeAll()
            // Save immediately on disappear
            saveStateImmediately()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background, .inactive:
                // Save immediately when app goes to background or becomes inactive
                logger.log("🔄 Scene phase changed to \(String(describing: newPhase)), saving state", category: "TabbedTreeView")
                saveStateImmediately()
            case .active:
                // App is active, normal operation
                break
            @unknown default:
                break
            }
        }
        // Note: avoid .onChange(of: tabs) since Array<TabModel> isn't Equatable in older SwiftUI
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            TabBarView(
                tabs: $tabs,
                selectedTabId: $selectedTabId,
                editingTabId: $editingTabId,
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
                    saveState()
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
        newTabName = ""
        showingNewTabDialog = true
    }

    private func createTabWithName(_ name: String) {
        let tabName = name.isEmpty ? "New Tab" : name
        let newTab = TabModel(title: tabName)
        tabs.append(newTab)
        selectedTabId = newTab.id
        saveState()
        setupFocusSubscriptions()
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
            saveState()
            setupFocusSubscriptions()
        }
    }

    private func updateTabTitle(_ tab: TabModel) {
        if let focusedId = tab.viewModel.focusedNodeId ?? tab.viewModel.selectedNodeId,
           let node = tab.viewModel.allNodes.first(where: { $0.id == focusedId }) {
            tab.title = String(node.title.prefix(20))
        } else {
            tab.title = "All Nodes"
        }
    }

    private func setupKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let currentTab = self.currentTab else { return event }
            let viewModel = currentTab.viewModel

            // Don't process if modals are showing
            if viewModel.showingDeleteAlert ||
               viewModel.showingCreateDialog ||
               viewModel.showingDetailsForNode != nil ||
               viewModel.showingTagPickerForNode != nil ||
               viewModel.showingHelpWindow ||
               self.showingNewTabDialog ||
               self.editingTabId != nil {
                return event
            }

            // Don't process if text field has focus
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                if firstResponder is NSTextView || firstResponder is NSTextField {
                    return event
                }
            }

            // Handle keyboard shortcuts
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 3: // F key - Focus (Cmd+Shift+F)
                    if event.modifierFlags.contains(.shift) {
                        logger.log("⌨️ Cmd+Shift+F pressed - focus on node", category: "TabbedTreeView")
                        if let selectedId = viewModel.selectedNodeId,
                           let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                            if selectedNode.nodeType != "note" {
                                viewModel.focusedNodeId = selectedNode.id
                                viewModel.expandedNodes.insert(selectedNode.id)
                                NotificationCenter.default.post(name: .focusChanged, object: nil)
                            }
                        }
                        return nil
                    }

                case 17: // T - tags/new tab
                    if event.modifierFlags.contains(.shift) {
                        // Cmd+Shift+T - New tab
                        self.addNewTab()
                        return nil
                    } else {
                        // Cmd+T - Tags
                        if let selectedId = viewModel.selectedNodeId,
                           let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                           selectedNode.nodeType != "smart_folder" {
                            viewModel.showingTagPickerForNode = selectedNode
                        }
                        return nil
                    }
                case 13: // W - close tab
                    if let tabId = self.selectedTabId {
                        self.closeTab(tabId)
                        return nil
                    }
                case 2: // D - details/delete
                    if event.modifierFlags.contains(.shift) {
                        // Cmd+Shift+D - Delete
                        if let selectedId = viewModel.selectedNodeId,
                           let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                            viewModel.deleteNode(selectedNode)
                        }
                        return nil
                    } else {
                        // Cmd+D - Details
                        if let selectedId = viewModel.selectedNodeId,
                           let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }) {
                            viewModel.showingDetailsForNode = selectedNode
                        }
                        return nil
                    }
                default:
                    break
                }
            }

            // Handle space bar for editing
            if event.keyCode == 49 { // Space
                if let selectedId = viewModel.selectedNodeId {
                    viewModel.isEditing = true
                    return nil
                }
            }

            // Handle creation shortcuts (T, F, N)
            switch event.keyCode {
            case 17 where !event.modifierFlags.contains(.command): // T - task
                viewModel.createNodeType = "task"
                viewModel.createNodeTitle = ""
                self.activeCreateVM = viewModel
                return nil
            case 3 where !event.modifierFlags.contains(.command): // F - folder
                viewModel.createNodeType = "folder"
                viewModel.createNodeTitle = ""
                self.activeCreateVM = viewModel
                return nil
            case 45: // N - note
                viewModel.createNodeType = "note"
                viewModel.createNodeTitle = ""
                self.activeCreateVM = viewModel
                return nil
            case 47: // . - toggle task
                if let selectedId = viewModel.selectedNodeId,
                   let selectedNode = viewModel.allNodes.first(where: { $0.id == selectedId }),
                   selectedNode.nodeType == "task" {
                    viewModel.toggleTaskStatus(selectedNode)
                    return nil
                }
            default:
                break
            }

            return event
        }
    }

    // MARK: - State Persistence

    private func saveState() {
        logger.log("📝 Queueing tab state save", category: "TabbedTreeView")

        let tabStates = tabs.map { tab in
            let focusedId = tab.viewModel.focusedNodeId ?? tab.viewModel.selectedNodeId
            logger.log("  Tab '\(tab.title)': focusedNodeId = \(focusedId ?? "nil")", category: "TabbedTreeView")
            return UIState.TabState(
                id: tab.id,
                title: tab.title,
                focusedNodeId: focusedId
            )
        }

        let state = UIState(tabs: tabStates)
        stateManager.saveState(state) // This is now debounced
    }

    private func saveStateImmediately() {
        logger.log("💾 Immediate tab state save", category: "TabbedTreeView")

        let tabStates = tabs.map { tab in
            let focusedId = tab.viewModel.focusedNodeId
            let selectedId = tab.viewModel.selectedNodeId
            let savedId = focusedId ?? selectedId
            logger.log("  Tab '\(tab.title)': focused=\(focusedId ?? "nil"), selected=\(selectedId ?? "nil"), saving=\(savedId ?? "nil")", category: "TabbedTreeView")
            return UIState.TabState(
                id: tab.id,
                title: tab.title,
                focusedNodeId: savedId
            )
        }

        let state = UIState(tabs: tabStates)
        stateManager.saveStateImmediately(state)
    }

    private func restoreState() {
        logger.log("📂 Restoring tab state", category: "TabbedTreeView")

        if let state = stateManager.loadState(), !state.tabs.isEmpty {
            logger.log("✅ Found saved state with \(state.tabs.count) tabs", category: "TabbedTreeView")

            // Create tabs from saved state
            tabs = state.tabs.map { tabState in
                TabModel(
                    id: tabState.id,
                    title: tabState.title,
                    focusedNodeId: tabState.focusedNodeId
                )
            }

            // Set each tab's DataManager
            for tab in tabs {
                tab.viewModel.setDataManager(dataManager)
            }

            // Load nodes for all tabs and restore focus
            Task {
                for (index, tabState) in state.tabs.enumerated() {
                    let tab = tabs[index]
                    await tab.viewModel.loadAllNodes()

                    // Restore focused node if it still exists
                    if let focusedId = tabState.focusedNodeId {
                        if let focusedNode = tab.viewModel.allNodes.first(where: { $0.id == focusedId }) {
                            // Re-set both focused node and selected node after loading
                            tab.viewModel.focusedNodeId = focusedId
                            tab.viewModel.selectedNodeId = focusedId

                            // Expand the focused node and all its ancestors
                            tab.viewModel.expandedNodes.insert(focusedId)

                            // Expand all parent nodes up to root
                            let parentChain = tab.viewModel.getParentChain(for: focusedNode)
                            for parent in parentChain {
                                tab.viewModel.expandedNodes.insert(parent.id)
                            }

                            logger.log("✅ Restored focus and selection for tab '\(tab.title)' to node: \(focusedId) with \(parentChain.count) expanded parents", category: "TabbedTreeView")
                        } else {
                            // Node was deleted, reset focus
                            tab.viewModel.focusedNodeId = nil
                            tab.viewModel.selectedNodeId = nil
                            logger.log("ℹ️ Focused node deleted for tab '\(tab.title)', reset to root", category: "TabbedTreeView")
                        }
                    }
                }
            }

            // Select first tab
            if let firstTab = tabs.first {
                selectedTabId = firstTab.id
            }
        } else {
            logger.log("ℹ️ No saved state, creating default tab", category: "TabbedTreeView")
            // No saved state, create default tab
            let defaultTab = TabModel(title: "Main")
            tabs = [defaultTab]
            selectedTabId = defaultTab.id
        }
    }

    private func setupStateChangeObservers() {
        // Remove any existing observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        // Listen for tab title changes
        let titleObserver = NotificationCenter.default.addObserver(
            forName: .tabStateChanged,
            object: nil,
            queue: .main
        ) { _ in
            self.saveState()
        }
        notificationObservers.append(titleObserver)

        // Also listen for app termination (macOS specific)
        let terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.logger.log("🛑 App terminating, saving state immediately", category: "TabbedTreeView")
            self.saveStateImmediately()
        }
        notificationObservers.append(terminationObserver)

        // Listen for focus changes broadcast by views
        let focusObserver = NotificationCenter.default.addObserver(
            forName: .focusChanged,
            object: nil,
            queue: .main
        ) { _ in
            self.logger.log("🧭 FocusChanged notification received — saving state", category: "TabbedTreeView")
            self.saveState()
        }
        notificationObservers.append(focusObserver)
    }

    private func setupFocusSubscriptions() {
        // Remove subscriptions for tabs that no longer exist
        let currentIds = Set(tabs.map { $0.id })
        for (id, sub) in focusSubscriptions where !currentIds.contains(id) {
            sub.cancel()
            focusSubscriptions.removeValue(forKey: id)
        }

        // Add subscriptions for any new tabs
        for tab in tabs {
            guard focusSubscriptions[tab.id] == nil else { continue }

            // Watch BOTH focusedNodeId and selectedNodeId changes
            let focusCancellable = tab.viewModel.$focusedNodeId
                .removeDuplicates { $0 == $1 }
                .sink { _ in
                    logger.log("🧭 Focus changed in tab '\(tab.title)' — saving immediately", category: "TabbedTreeView")
                    saveStateImmediately()
                }

            let selectionCancellable = tab.viewModel.$selectedNodeId
                .removeDuplicates { $0 == $1 }
                .sink { _ in
                    logger.log("🎯 Selection changed in tab '\(tab.title)' — saving immediately", category: "TabbedTreeView")
                    saveStateImmediately()
                }

            // Combine both subscriptions
            let combined = AnyCancellable {
                focusCancellable.cancel()
                selectionCancellable.cancel()
            }

            focusSubscriptions[tab.id] = combined
        }
    }
}

struct TabBarView: View {
    @Binding var tabs: [TabModel]
    @Binding var selectedTabId: UUID?
    @Binding var editingTabId: UUID?
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
                            isEditing: editingTabId == tab.id,
                            onSelect: { selectedTabId = tab.id },
                            onClose: { onCloseTab(tab.id) },
                            onStartEdit: { editingTabId = tab.id },
                            onEndEdit: { editingTabId = nil }
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
    let isEditing: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onStartEdit: () -> Void
    let onEndEdit: () -> Void

    @State private var isHovering = false
    @State private var editText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var lastClickTime = Date.distantPast

    var body: some View {
        HStack(spacing: 4) {
            if tab.viewModel.focusedNodeId != nil {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if isEditing {
                TextField("Tab name", text: $editText, onCommit: {
                    if !editText.isEmpty {
                        tab.title = editText
                    }
                    onEndEdit()
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(maxWidth: 120)
                .focused($isTextFieldFocused)
                .onAppear {
                    editText = tab.title
                    DispatchQueue.main.async {
                        isTextFieldFocused = true
                    }
                }
            } else {
                Text(tab.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120)
            }

            if (isSelected || isHovering) && !isEditing {
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
            let now = Date()
            if isSelected && now.timeIntervalSince(lastClickTime) < 0.5 {
                // Double-click on selected tab - start editing
                onStartEdit()
            } else {
                onSelect()
            }
            lastClickTime = now
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct NewTabSheet: View {
    @Binding var tabName: String
    let onCreateTab: () -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("New Tab")
                .font(.headline)
                .padding(.top, 4)

            TextField("Enter tab name", text: $tabName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    onCreateTab()
                }
                .frame(minWidth: 250)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    onCreateTab()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 300)
        .onAppear {
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }
}

#endif
