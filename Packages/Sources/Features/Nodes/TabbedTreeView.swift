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
            // Mark as user-overridden when explicitly set (not from focus update)
            if !isUpdatingFromFocus {
                hasUserOverriddenName = true
            }
            // Notify TabbedTreeView to save state when title changes
            NotificationCenter.default.post(name: .tabStateChanged, object: nil)
        }
    }
    public let viewModel: TreeViewModel
    private var cancellables = Set<AnyCancellable>()
    private var hasUserOverriddenName: Bool = false
    private var isUpdatingFromFocus: Bool = false

    public init(id: UUID = UUID(), title: String = "All Nodes", focusedNodeId: String? = nil) {
        self.id = id
        self.title = title
        self.viewModel = TreeViewModel()
        self.viewModel.focusedNodeId = focusedNodeId

        // Mark as user-overridden if a non-default title is provided
        if title != "All Nodes" && title != "New Tab" {
            self.hasUserOverriddenName = true
        }

        // Only forward viewModel changes to trigger view updates
        // Focus/selection subscriptions are handled at TabbedTreeView level for active tab only
        self.viewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Subscribe to focus changes to update tab name (if not user-overridden)
        setupFocusSubscription()
    }

    private func setupFocusSubscription() {
        viewModel.$focusedNode
            .removeDuplicates { $0?.id == $1?.id } // Only update when node actually changes
            .sink { [weak self] node in
                guard let self = self,
                      !self.hasUserOverriddenName else { return }

                // Update tab name based on focused node
                self.isUpdatingFromFocus = true
                self.title = node?.title ?? "All Nodes"
                self.isUpdatingFromFocus = false
            }
            .store(in: &cancellables)
    }

    /// Reset the user override flag to allow automatic naming again
    public func resetToAutomaticNaming() {
        hasUserOverriddenName = false
        // Trigger an update based on current focus
        if let focusedNode = viewModel.focusedNode {
            isUpdatingFromFocus = true
            title = focusedNode.title
            isUpdatingFromFocus = false
        } else {
            isUpdatingFromFocus = true
            title = "All Nodes"
            isUpdatingFromFocus = false
        }
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
    @State private var showingNewTabDialog = false
    @State private var newTabName = ""
    @State private var editingTabId: UUID?
    @State private var keyEventMonitor: Any?
    @State private var hasRestoredState = false
    @State private var notificationObservers: [NSObjectProtocol] = []
    @State private var activeTabSubscription: AnyCancellable?
    private let stateManager = UIStateManager.shared
    private let logger = Logger.shared

    public init() {}

    private var currentTab: TabModel? {
        tabs.first { $0.id == selectedTabId }
    }

    public var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(currentTab?.viewModel.focusedNode?.title ?? "All Nodes")
                .toolbar {
                    toolbarContent
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
            // Cancel active tab subscription
            activeTabSubscription?.cancel()
            activeTabSubscription = nil
            // Save on disappear
            self.saveStateNow()
        }
        .onChange(of: selectedTabId) { _ in
            setupActiveTabSubscription()
            saveStateNow() // Save on tab change
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background, .inactive:
                // Save immediately when app goes to background or becomes inactive
                logger.log("🔄 Scene phase changed to \(String(describing: newPhase)), saving state", category: "TabbedTreeView")
                self.saveStateNow()
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
                onCloseTab: { closeTab($0) },
                onTabChange: { saveStateNow() }
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
                // Removed .id() modifier which was causing view recreation
                // and breaking @ObservedObject observation of @Published properties
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let currentTab = currentTab {
            ToolbarItem(placement: .cancellationAction) {
                HStack(spacing: 8) {
                    NetworkStatusIndicator(lastSyncDate: dataManager.lastSyncDate)

                    Button(action: {
                        currentTab.viewModel.showCompletedTasks.toggle()
                    }) {
                        Image(systemName: currentTab.viewModel.showCompletedTasks ? "eye" : "eye.slash")
                    }
                    .help(currentTab.viewModel.showCompletedTasks ? "Hide completed tasks" : "Show completed tasks")

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
                        currentTab.viewModel.showingCreateDialog = true
                    }
                    Button("Task") {
                        currentTab.viewModel.createNodeType = "task"
                        currentTab.viewModel.createNodeTitle = ""
                        currentTab.viewModel.showingCreateDialog = true
                    }
                    Button("Note") {
                        currentTab.viewModel.createNodeType = "note"
                        currentTab.viewModel.createNodeTitle = ""
                        currentTab.viewModel.showingCreateDialog = true
                    }
                    Button("Template") {
                        currentTab.viewModel.createNodeType = "template"
                        currentTab.viewModel.createNodeTitle = ""
                        currentTab.viewModel.showingCreateDialog = true
                    }
                    Button("Smart Folder") {
                        currentTab.viewModel.createNodeType = "smart_folder"
                        currentTab.viewModel.createNodeTitle = ""
                        currentTab.viewModel.showingCreateDialog = true
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

        // If user provided a custom name, mark it as overridden
        // Otherwise, let it use automatic naming based on focus
        if !name.isEmpty {
            // This will trigger the didSet which marks it as user-overridden
            newTab.title = tabName
        }

        // Set the DataManager and load initial data
        newTab.viewModel.setDataManager(dataManager)
        Task {
            await newTab.viewModel.initialLoad()
        }

        tabs.append(newTab)
        selectedTabId = newTab.id
        // onChange(of: selectedTabId) will handle subscription setup and saving
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
            // onChange(of: selectedTabId) will handle subscription setup and saving
        }
    }


    private func setupKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ATTEMPT 8: Add diagnostic logging
            logger.log("🔵 MONITOR ALIVE: Received keyDown event", category: "KEYBOARD-MONITOR")

            // ATTEMPT 9: Log the state of showingTagPickerForNode
            if let currentTab = self.currentTab {
                if currentTab.viewModel.showingTagPickerForNode != nil {
                    logger.log("⚠️ ATTEMPT 9: showingTagPickerForNode is SET - would normally block", category: "KEYBOARD-MODAL")
                }
            }

            guard let currentTab = self.currentTab else {
                logger.log("⚠️ No current tab available", category: "KEYBOARD-MONITOR")
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
            // ATTEMPT 9: Commented out showingTagPickerForNode check - it blocks keyboard when sheet doesn't present
            if self.showingNewTabDialog ||
               self.editingTabId != nil ||
               viewModel.showingDeleteAlert ||
               viewModel.showingCreateDialog ||
               viewModel.showingDetailsForNode != nil ||
               // viewModel.showingTagPickerForNode != nil ||  // ATTEMPT 9: DISABLED
               viewModel.showingNoteEditorForNode != nil ||
               viewModel.showingHelpWindow ||
               viewModel.isEditing {
                logger.log("🚫 Modal active - returning event to modal", category: "KEYBOARD-MODAL")
                // IMPORTANT: Return here to prevent TreeViewModel from handling the key
                // This allows the note editor's TextEditor to handle Cmd+C for copy
                return event
            }

            let keyCode = event.keyCode
            let modifiers = event.modifierFlags

            // MARK: - Tab Management (Cmd shortcuts)
            if modifiers.contains(.command) {
                logger.log("🎯 Processing COMMAND key combination", category: "KEYBOARD")
                switch keyCode {
                // System shortcuts - pass through to macOS
                case 12: // Cmd+Q - Quit
                    logger.log("✅ Cmd+Q - passing through to system", category: "KEYBOARD")
                    return event

                case 17: // Cmd+Shift+T - New tab
                    if modifiers.contains(.shift) {
                        logger.log("✅ HANDLED: Cmd+Shift+T - New tab", category: "KEYBOARD")
                        self.addNewTab()
                        return nil
                    }
                    logger.log("🔄 Cmd+T (not Shift) - falling through for tags", category: "KEYBOARD")
                    // Fall through for Cmd+T (tags)
                    break

                case 13: // Cmd+W - Close tab
                    if let tabId = self.selectedTabId {
                        logger.log("✅ HANDLED: Cmd+W - Close tab", category: "KEYBOARD")
                        self.closeTab(tabId)
                        return nil
                    }
                    logger.log("⚠️ Cmd+W but no selected tab", category: "KEYBOARD")
                    break

                // Tab switching
                case 18: // Cmd+1
                    if tabs.count >= 1 {
                        selectedTabId = tabs[0].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 19: // Cmd+2
                    if tabs.count >= 2 {
                        selectedTabId = tabs[1].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 20: // Cmd+3
                    if tabs.count >= 3 {
                        selectedTabId = tabs[2].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 21: // Cmd+4
                    if tabs.count >= 4 {
                        selectedTabId = tabs[3].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 23: // Cmd+5
                    if tabs.count >= 5 {
                        selectedTabId = tabs[4].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 22: // Cmd+6
                    if tabs.count >= 6 {
                        selectedTabId = tabs[5].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 26: // Cmd+7
                    if tabs.count >= 7 {
                        selectedTabId = tabs[6].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 28: // Cmd+8
                    if tabs.count >= 8 {
                        selectedTabId = tabs[7].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }
                case 25: // Cmd+9
                    if tabs.count >= 9 {
                        selectedTabId = tabs[8].id
                        // onChange(of: selectedTabId) will handle subscription setup and saving
                        return nil
                    }

                case 124: // Cmd+Right Arrow - Next tab
                    if let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabId }) {
                        let nextIndex = (currentIndex + 1) % tabs.count
                        selectedTabId = tabs[nextIndex].id
                        logger.log("✅ HANDLED: Cmd+Right Arrow - Switch to next tab", category: "KEYBOARD")
                        return nil
                    }

                case 123: // Cmd+Left Arrow - Previous tab
                    if let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabId }) {
                        let previousIndex = currentIndex > 0 ? currentIndex - 1 : tabs.count - 1
                        selectedTabId = tabs[previousIndex].id
                        logger.log("✅ HANDLED: Cmd+Left Arrow - Switch to previous tab", category: "KEYBOARD")
                        return nil
                    }

                default:
                    break
                }
            }

            // MARK: - All Node Operations - Delegate to TreeViewModel
            // This includes arrow keys, creation shortcuts, etc.
            logger.log("🔄 DELEGATING to TreeViewModel.handleKeyPress", category: "KEYBOARD")
            logger.log("  - selectedNodeId: \(viewModel.selectedNodeId ?? "nil")", category: "KEYBOARD")
            logger.log("  - focusedNodeId: \(viewModel.focusedNodeId ?? "nil")", category: "KEYBOARD")

            // ATTEMPT 8: Add exception handling
            do {
                let handled = viewModel.handleKeyPress(keyCode: keyCode, modifiers: modifiers)

                // Special diagnostic for Cmd+T
                if modifiers.contains(.command) && keyCode == 17 {
                    logger.log("🔍 ATTEMPT 8: Cmd+T handling result: \(handled)", category: "KEYBOARD-MONITOR")
                    logger.log("  - Monitor still active: \(self.keyEventMonitor != nil)", category: "KEYBOARD-MONITOR")
                    logger.log("  - showingTagPickerForNode: \(viewModel.showingTagPickerForNode?.title ?? "nil")", category: "KEYBOARD-MONITOR")
                }

                if handled {
                    logger.log("✅✅✅ TreeViewModel HANDLED the key - returning nil", category: "KEYBOARD")
                    return nil
                } else {
                    // Pass through all unhandled events to the system
                    // This ensures keyboard shortcuts don't break
                    logger.log("❌ TreeViewModel DID NOT handle key - passing through", category: "KEYBOARD")
                    return event
                }
            } catch {
                logger.log("❌ ATTEMPT 8: EXCEPTION in handleKeyPress: \(error)", category: "KEYBOARD-ERROR", level: .error)
                return event
            }
        }
    }

    // MARK: - State Persistence

    private func updateState() {
        logger.log("📝 Updating in-memory state", category: "TabbedTreeView")

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
        stateManager.updateState(state) // Update in-memory state
    }

    private func saveStateNow() {
        logger.log("💾 Saving state to disk now", category: "TabbedTreeView")

        let tabStates = tabs.map { tab in
            let focusedId = tab.viewModel.focusedNodeId ?? tab.viewModel.selectedNodeId
            return UIState.TabState(
                id: tab.id,
                title: tab.title,
                focusedNodeId: focusedId
            )
        }

        let state = UIState(tabs: tabStates)
        stateManager.updateState(state) // Update in-memory
        stateManager.saveStateNow() // Force save to disk
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

            // Select first tab and setup subscription
            if let firstTab = tabs.first {
                selectedTabId = firstTab.id
                setupActiveTabSubscription() // Initial setup for first tab
            }
        } else {
            logger.log("ℹ️ No saved state, creating default tab", category: "TabbedTreeView")
            // No saved state, create default tab
            let defaultTab = TabModel(title: "Main")
            tabs = [defaultTab]
            selectedTabId = defaultTab.id
            setupActiveTabSubscription() // Initial setup for default tab
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
            self.updateState()
        }
        notificationObservers.append(titleObserver)

        // Also listen for app termination (macOS specific)
        let terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.logger.log("🛑 App terminating, saving state immediately", category: "TabbedTreeView")
            self.saveStateNow()
        }
        notificationObservers.append(terminationObserver)

        // Removed focusChanged observer - now handled by active tab subscription
    }

    private func setupActiveTabSubscription() {
        // Cancel any existing subscription
        activeTabSubscription?.cancel()
        activeTabSubscription = nil

        // Subscribe only to the currently active tab
        guard let activeTab = currentTab else { return }

        // Watch BOTH focusedNodeId and selectedNodeId changes for active tab only
        let focusCancellable = activeTab.viewModel.$focusedNodeId
            .removeDuplicates { $0 == $1 }
            .sink { _ in
                logger.log("🧭 Focus changed in active tab '\(activeTab.title)' — updating state", category: "TabbedTreeView")
                updateState()
            }

        let selectionCancellable = activeTab.viewModel.$selectedNodeId
            .removeDuplicates { $0 == $1 }
            .sink { _ in
                logger.log("🎯 Selection changed in active tab '\(activeTab.title)' — updating state", category: "TabbedTreeView")
                updateState()
            }

        // Combine both subscriptions
        activeTabSubscription = AnyCancellable {
            focusCancellable.cancel()
            selectionCancellable.cancel()
        }
    }
}

struct TabBarView: View {
    @Binding var tabs: [TabModel]
    @Binding var selectedTabId: UUID?
    @Binding var editingTabId: UUID?
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onTabChange: () -> Void

    @State private var draggedTab: TabModel?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabs) { tab in
                        TabBarItem(
                            tab: tab,
                            isSelected: tab.id == selectedTabId,
                            isEditing: editingTabId == tab.id,
                            canClose: tabs.count > 1,
                            onSelect: {
                                if selectedTabId != tab.id {
                                    selectedTabId = tab.id
                                    // onChange(of: selectedTabId) will handle everything
                                }
                            },
                            onClose: { onCloseTab(tab.id) },
                            onStartEdit: { editingTabId = tab.id },
                            onEndEdit: { editingTabId = nil }
                        )
                        .opacity(draggedTab?.id == tab.id ? 0.5 : 1.0)
                        .onDrag {
                            self.draggedTab = tab
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(
                            tab: tab,
                            tabs: $tabs,
                            draggedTab: $draggedTab,
                            onTabChange: onTabChange
                        ))
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
    let canClose: Bool
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

            if (isSelected || isHovering) && !isEditing && canClose {
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

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tab: TabModel
    @Binding var tabs: [TabModel]
    @Binding var draggedTab: TabModel?
    let onTabChange: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTab = draggedTab,
              draggedTab.id != tab.id,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedTab.id }),
              let toIndex = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTab = nil
        onTabChange() // Save the new tab order
        return true
    }
}

#endif
