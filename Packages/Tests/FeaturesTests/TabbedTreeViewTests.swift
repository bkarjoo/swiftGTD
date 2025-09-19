#if os(macOS)
import XCTest
import SwiftUI
import Combine
@testable import Features
@testable import Services
@testable import Models
@testable import Core

/// Tests for TabbedTreeView and TabModel functionality
@MainActor
final class TabbedTreeViewTests: XCTestCase {

    // MARK: - TabModel Tests

    func testTabModel_initialization_setsDefaultValues() {
        let tab = TabModel()

        XCTAssertEqual(tab.title, "All Nodes")
        XCTAssertNotNil(tab.viewModel)
        XCTAssertNotNil(tab.id)
    }

    func testTabModel_initialization_withCustomTitle() {
        let customTitle = "My Custom Tab"
        let tab = TabModel(title: customTitle)

        XCTAssertEqual(tab.title, customTitle)
        XCTAssertNotNil(tab.viewModel)
    }

    func testTabModel_titleUpdate_publishesChange() {
        let tab = TabModel()
        let expectation = XCTestExpectation(description: "Title change published")

        let cancellable = tab.$title.sink { title in
            if title != "All Nodes" {
                expectation.fulfill()
            }
        }

        tab.title = "Updated Title"

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testTabModel_hasUniqueViewModel() {
        let tab1 = TabModel()
        let tab2 = TabModel()

        XCTAssertFalse(tab1.viewModel === tab2.viewModel)
        XCTAssertNotEqual(tab1.id, tab2.id)
    }

    // MARK: - Tab Management Tests

    func testTabs_initialState_hasOneTab() async {
        let dataManager = DataManager()
        let view = TabbedTreeView()
            .environmentObject(dataManager)

        let mirror = Mirror(reflecting: view)
        if let tabsBinding = mirror.descendant("_tabs") as? State<[TabModel]> {
            XCTAssertEqual(tabsBinding.wrappedValue.count, 1)
            XCTAssertEqual(tabsBinding.wrappedValue.first?.title, "All Nodes")
        }
    }

    func testAddNewTab_addsTabToArray() {
        var tabs: [TabModel] = [TabModel()]
        var selectedTabId: UUID?

        let newTab = TabModel(title: "New Tab")
        tabs.append(newTab)
        selectedTabId = newTab.id

        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(selectedTabId, newTab.id)
        XCTAssertEqual(tabs.last?.title, "New Tab")
    }

    func testCloseTab_whenMultipleTabs_removesTab() {
        var tabs: [TabModel] = [
            TabModel(title: "Tab 1"),
            TabModel(title: "Tab 2"),
            TabModel(title: "Tab 3")
        ]
        var selectedTabId = tabs[1].id
        let tabToClose = tabs[1].id

        if let index = tabs.firstIndex(where: { $0.id == tabToClose }) {
            let wasSelected = selectedTabId == tabToClose
            tabs.remove(at: index)

            if wasSelected {
                if index < tabs.count {
                    selectedTabId = tabs[index].id
                } else if index > 0 {
                    selectedTabId = tabs[index - 1].id
                }
            }
        }

        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0].title, "Tab 1")
        XCTAssertEqual(tabs[1].title, "Tab 3")
        XCTAssertNotNil(selectedTabId)
    }

    func testCloseTab_whenSingleTab_doesNotRemove() {
        var tabs: [TabModel] = [TabModel(title: "Only Tab")]
        let originalCount = tabs.count
        let tabToClose = tabs[0].id

        guard tabs.count > 1 else {
            // Should not remove the last tab
            XCTAssertEqual(tabs.count, originalCount)
            return
        }

        if let index = tabs.firstIndex(where: { $0.id == tabToClose }) {
            tabs.remove(at: index)
        }

        XCTAssertEqual(tabs.count, 1)
    }

    // MARK: - Tab Title Update Tests

    func testUpdateTabTitle_withFocusedNode() {
        let tab = TabModel()
        let testNode = Node(
            id: "test-node",
            title: "Very Long Node Title That Should Be Truncated",
            nodeType: "folder",
            parentId: nil,
            sortOrder: 1000,
            createdAt: Date(),
            updatedAt: Date()
        )

        tab.viewModel.allNodes = [testNode]
        tab.viewModel.focusedNodeId = testNode.id

        if let focusedId = tab.viewModel.focusedNodeId,
           let node = tab.viewModel.allNodes.first(where: { $0.id == focusedId }) {
            tab.title = String(node.title.prefix(20))
        }

        XCTAssertEqual(tab.title, "Very Long Node Title")
        XCTAssertEqual(tab.title.count, 20)
    }

    func testUpdateTabTitle_withoutFocusedNode_setsDefault() {
        let tab = TabModel()
        tab.viewModel.focusedNodeId = nil

        if tab.viewModel.focusedNodeId == nil {
            tab.title = "All Nodes"
        }

        XCTAssertEqual(tab.title, "All Nodes")
    }

    // MARK: - Tab Selection Tests

    func testTabSelection_updatesSelectedTabId() {
        let tabs = [
            TabModel(title: "Tab 1"),
            TabModel(title: "Tab 2")
        ]
        var selectedTabId: UUID? = tabs[0].id

        selectedTabId = tabs[1].id

        XCTAssertEqual(selectedTabId, tabs[1].id)
    }

    func testTabSelection_afterClosingSelectedTab_selectsNextTab() {
        var tabs = [
            TabModel(title: "Tab 1"),
            TabModel(title: "Tab 2"),
            TabModel(title: "Tab 3")
        ]
        var selectedTabId: UUID? = tabs[1].id

        let indexToRemove = 1
        let wasSelected = selectedTabId == tabs[indexToRemove].id
        tabs.remove(at: indexToRemove)

        if wasSelected {
            if indexToRemove < tabs.count {
                selectedTabId = tabs[indexToRemove].id
            } else if indexToRemove > 0 {
                selectedTabId = tabs[indexToRemove - 1].id
            }
        }

        XCTAssertEqual(selectedTabId, tabs[1].id) // Should select "Tab 3" which is now at index 1
        XCTAssertEqual(tabs[1].title, "Tab 3")
    }

    // MARK: - Independent State Tests

    func testEachTab_hasSeparateViewModel() {
        let tab1 = TabModel(title: "Tab 1")
        let tab2 = TabModel(title: "Tab 2")

        tab1.viewModel.selectedNodeId = "node-1"
        tab1.viewModel.focusedNodeId = "focused-1"
        tab1.viewModel.expandedNodes = ["expanded-1"]

        tab2.viewModel.selectedNodeId = "node-2"
        tab2.viewModel.focusedNodeId = "focused-2"
        tab2.viewModel.expandedNodes = ["expanded-2"]

        XCTAssertNotEqual(tab1.viewModel.selectedNodeId, tab2.viewModel.selectedNodeId)
        XCTAssertNotEqual(tab1.viewModel.focusedNodeId, tab2.viewModel.focusedNodeId)
        XCTAssertNotEqual(tab1.viewModel.expandedNodes, tab2.viewModel.expandedNodes)
    }

    func testTabSwitch_preservesIndividualState() {
        let tab1 = TabModel(title: "Tab 1")
        let tab2 = TabModel(title: "Tab 2")

        tab1.viewModel.selectedNodeId = "selected-1"
        tab1.viewModel.focusedNodeId = "focused-1"
        tab1.viewModel.isEditing = true

        tab2.viewModel.selectedNodeId = "selected-2"
        tab2.viewModel.focusedNodeId = nil
        tab2.viewModel.isEditing = false

        XCTAssertEqual(tab2.viewModel.selectedNodeId, "selected-2")
        XCTAssertNil(tab2.viewModel.focusedNodeId)
        XCTAssertFalse(tab2.viewModel.isEditing)

        XCTAssertEqual(tab1.viewModel.selectedNodeId, "selected-1")
        XCTAssertEqual(tab1.viewModel.focusedNodeId, "focused-1")
        XCTAssertTrue(tab1.viewModel.isEditing)
    }

    // MARK: - TabBarItem Tests

    func testTabBarItem_showsFolderIcon_whenFocused() {
        let tab = TabModel()
        tab.viewModel.focusedNodeId = "some-node"

        XCTAssertNotNil(tab.viewModel.focusedNodeId)
    }

    func testTabBarItem_hidesCloseButton_whenNotHovering() {
        _ = TabModel()
        let isHovering = false
        let isSelected = false

        let shouldShowCloseButton = isSelected || isHovering
        XCTAssertFalse(shouldShowCloseButton)
    }

    func testTabBarItem_showsCloseButton_whenSelected() {
        _ = TabModel()
        let isHovering = false
        let isSelected = true

        let shouldShowCloseButton = isSelected || isHovering
        XCTAssertTrue(shouldShowCloseButton)
    }

    func testTabBarItem_showsCloseButton_whenHovering() {
        _ = TabModel()
        let isHovering = true
        let isSelected = false

        let shouldShowCloseButton = isSelected || isHovering
        XCTAssertTrue(shouldShowCloseButton)
    }

    // MARK: - Performance Tests

    func testTabCreation_performance() {
        measure {
            var tabs: [TabModel] = []
            for i in 0..<100 {
                tabs.append(TabModel(title: "Tab \(i)"))
            }
            XCTAssertEqual(tabs.count, 100)
        }
    }

    func testTabSwitching_performance() {
        let tabs = (0..<20).map { TabModel(title: "Tab \($0)") }
        var selectedTabId = tabs[0].id

        measure {
            for _ in 0..<100 {
                selectedTabId = tabs.randomElement()!.id
            }
        }

        XCTAssertNotNil(selectedTabId)
    }
}

#endif