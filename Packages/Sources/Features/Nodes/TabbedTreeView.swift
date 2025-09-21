#if os(macOS)
import SwiftUI
import Combine
import Core
import Models
import Services
import Networking

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
                        .onDisappear {
                            // Ensure showingCreateDialog is reset when sheet is dismissed
                            viewModel.showingCreateDialog = false
                        }
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
                    saveState()
                }
                .onChange(of: currentTab.viewModel.showingCreateDialog) { isShowing in
                    if isShowing {
                        // Set activeCreateVM when keyboard shortcut triggers create dialog
                        activeCreateVM = currentTab.viewModel
                    } else if activeCreateVM?.id == currentTab.viewModel.id {
                        // Clear activeCreateVM when dialog is dismissed
                        activeCreateVM = nil
                    }
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


    private func setupKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let currentTab = self.currentTab else {
                return event
            }
            let viewModel = currentTab.viewModel

            // Don't process if text field has focus
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                if firstResponder is NSTextView || firstResponder is NSTextField {
                    return event
                }
            }

            // Don't process if ANY modal is showing
            if self.showingNewTabDialog ||
               self.editingTabId != nil ||
               viewModel.showingDeleteAlert ||
               viewModel.showingCreateDialog ||
               viewModel.showingDetailsForNode != nil ||
               viewModel.showingTagPickerForNode != nil ||
               viewModel.showingNoteEditorForNode != nil ||
               viewModel.showingHelpWindow ||
               viewModel.isEditing {
                return event
            }

            let keyCode = event.keyCode
            let modifiers = event.modifierFlags

            // MARK: - Tab Management (Cmd shortcuts)
            if modifiers.contains(.command) {
                switch keyCode {
                case 17: // Cmd+Shift+T - New tab
                    if modifiers.contains(.shift) {
                        self.addNewTab()
                        return nil
                    }
                    // Fall through for Cmd+T (tags)

                case 13: // Cmd+W - Close tab
                    if let tabId = self.selectedTabId {
                        self.closeTab(tabId)
                        return nil
                    }

                // Tab switching
                case 18: // Cmd+1
                    if tabs.count >= 1 {
                        selectedTabId = tabs[0].id
                        return nil
                    }
                case 19: // Cmd+2
                    if tabs.count >= 2 {
                        selectedTabId = tabs[1].id
                        return nil
                    }
                case 20: // Cmd+3
                    if tabs.count >= 3 {
                        selectedTabId = tabs[2].id
                        return nil
                    }
                case 21: // Cmd+4
                    if tabs.count >= 4 {
                        selectedTabId = tabs[3].id
                        return nil
                    }
                case 23: // Cmd+5
                    if tabs.count >= 5 {
                        selectedTabId = tabs[4].id
                        return nil
                    }
                case 22: // Cmd+6
                    if tabs.count >= 6 {
                        selectedTabId = tabs[5].id
                        return nil
                    }
                case 26: // Cmd+7
                    if tabs.count >= 7 {
                        selectedTabId = tabs[6].id
                        return nil
                    }
                case 28: // Cmd+8
                    if tabs.count >= 8 {
                        selectedTabId = tabs[7].id
                        return nil
                    }
                case 25: // Cmd+9
                    if tabs.count >= 9 {
                        selectedTabId = tabs[8].id
                        return nil
                    }

                default:
                    break
                }
            }

            // MARK: - All Node Operations - Delegate to TreeViewModel
            // This includes arrow keys, creation shortcuts, etc.
            if viewModel.handleKeyPress(keyCode: keyCode, modifiers: modifiers) {
                return nil
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
                    await tab.viewModel.initialLoad()

                    // Restore focused node if it still exists
                    if let focusedId = tabState.focusedNodeId {
                        if let focusedNode = tab.viewModel.allNodes.first(where: { $0.id == focusedId }) {
                            // Re-set both focused node and selected node after loading
                            tab.viewModel.setFocusedNode(focusedId)
                            tab.viewModel.setSelectedNode(focusedId)

                            // Expand all parent nodes up to root
                            let parentChain = tab.viewModel.getParentChain(for: focusedNode)
                            for parent in parentChain {
                                tab.viewModel.expandNode(parent.id)
                            }

                            logger.log("✅ Restored focus and selection for tab '\(tab.title)' to node: \(focusedId) with \(parentChain.count) expanded parents", category: "TabbedTreeView")
                        } else {
                            // Node was deleted, reset focus
                            tab.viewModel.setFocusedNode(nil)
                            tab.viewModel.setSelectedNode(nil)
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

    private func copyNodeNamesToClipboard(viewModel: TreeViewModel) {
        logger.log("📋 Copying node names to clipboard", category: "TabbedTreeView")

        var textToCopy = ""

        // Get the nodes to copy based on focus state
        if let focusedId = viewModel.focusedNodeId {
            // In focus mode - copy the focused node and its direct children
            if let focusedNode = viewModel.allNodes.first(where: { $0.id == focusedId }) {
                textToCopy = focusedNode.title + "\n"

                // Get direct children only (not nested)
                let children = viewModel.getChildren(of: focusedId)
                for child in children {
                    textToCopy += "- " + child.title + "\n"
                }
            }
        } else {
            // Not in focus mode - copy all root nodes
            textToCopy = "All Nodes\n"
            let rootNodes = viewModel.getRootNodes()
            for node in rootNodes {
                textToCopy += "- " + node.title + "\n"
            }
        }

        // Copy to clipboard
        if !textToCopy.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            logger.log("✅ Copied \(textToCopy.components(separatedBy: "\n").count - 1) node names to clipboard", category: "TabbedTreeView")
        }
    }

    private func handleQuickAddToDefaultFolder(viewModel: TreeViewModel) async {
        // Get the default folder ID
        guard let defaultNodeId = await dataManager.getDefaultFolder() else {
            logger.log("⚠️ No default folder set", level: .warning, category: "TabbedTreeView")
            // Could show an alert here if desired
            return
        }

        // Find the default folder in the current nodes
        guard let defaultFolder = viewModel.allNodes.first(where: { $0.id == defaultNodeId }) else {
            logger.log("⚠️ Default folder not found in nodes", level: .warning, category: "TabbedTreeView")
            return
        }

        logger.log("✅ Quick add to default folder: \(defaultFolder.title)", category: "TabbedTreeView")

        // Set up for creating a task in the default folder
        viewModel.createNodeType = "task"
        viewModel.createNodeTitle = ""
        viewModel.createNodeParentId = defaultNodeId  // Set the explicit parent ID

        // Show the create dialog
        self.activeCreateVM = viewModel
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
