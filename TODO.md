# TODO: Architecture Refactoring Plan

## Overview
This refactoring addresses architectural issues identified in code review, focusing on establishing single source of truth, consistent data flow, and proper separation of concerns.

## Phase 1: Centralize API Operations in Services Layer
**Goal**: Remove all direct APIClient calls from views and route through DataManager

### Tasks
- [ ] Move default folder API calls from views to DataManager
  - [ ] Add `getDefaultFolder()` and `setDefaultFolder()` methods to DataManager
  - [ ] Update TreeView_macOS and TabbedTreeView to use DataManager methods
- [ ] Move template instantiation from views to DataManager
  - [ ] Add `instantiateTemplate(template:)` method to DataManager
  - [ ] Remove inline instantiation from TreeView_macOS
- [ ] Move smart folder execution to DataManager
  - [ ] Add `executeSmartFolder(node:)` method to DataManager
  - [ ] Update all call sites

### Testing Checkpoint 1
- [ ] Verify Q key still creates tasks in default folder
- [ ] Verify Cmd+U still instantiates templates correctly
- [ ] Verify smart folder execution still works
- [ ] Verify no direct APIClient calls remain in Features module

## Phase 2: Single Source of Truth
**Goal**: TreeViewModel should only subscribe to DataManager.nodes, never maintain separate state

### Tasks
- [ ] Remove TreeViewModel.allNodes as separate state
  - [ ] Make allNodes a computed property from DataManager.nodes
  - [ ] Update all references to use DataManager as source
- [ ] Ensure nodeChildren is derived from DataManager.nodes
  - [ ] Create single update method that builds nodeChildren from nodes
  - [ ] Remove all direct nodeChildren mutations
- [ ] Remove redundant node storage patterns
  - [ ] Audit for any other duplicate node storage
  - [ ] Consolidate to DataManager.nodes only

### Testing Checkpoint 2
- [ ] Verify tree view still displays correctly
- [ ] Verify selection/focus/expansion states persist
- [ ] Verify drag and drop reordering works
- [ ] Verify no duplicate node states exist

## Phase 3: Fix Refresh Semantics
**Goal**: Clear, predictable refresh behavior without footguns

### Tasks
- [ ] Rename loadAllNodes() to initialLoad()
  - [ ] Make it clear this only runs once with didLoad guard
  - [ ] Update all call sites that expect refresh to use appropriate method
- [ ] Standardize on refreshNodes() for full refresh
  - [ ] Ensure it always fetches fresh data
  - [ ] Update all refresh call sites to use this
- [ ] Implement targeted refresh properly
  - [ ] Create refreshNode(nodeId:) that updates node and its children
  - [ ] Ensure it merges children into main nodes array
  - [ ] Maintain allNodes/nodeChildren consistency

### Testing Checkpoint 3
- [ ] Verify initial load works on app start
- [ ] Verify pull-to-refresh works on iOS
- [ ] Verify refresh button works on macOS
- [ ] Verify template instantiation refreshes correctly
- [ ] Verify node creation/deletion updates tree properly

## Phase 4: Centralize UI Operations
**Goal**: Move keyboard and menu actions to ViewModel intent methods

### Tasks
- [ ] Create intent methods in TreeViewModel
  - [ ] `handleKeyPress(keyCode:modifiers:)` - centralized keyboard handling
  - [ ] `performNodeAction(action:nodeId:)` - menu/context actions
  - [ ] `navigateToNode(direction:)` - navigation intents
- [ ] Move keyboard handling logic from views to ViewModel
  - [ ] TreeView_macOS should only capture events and forward to ViewModel
  - [ ] TabbedTreeView should delegate to tab's ViewModel
- [ ] Centralize selection/focus/expansion state changes
  - [ ] Create single methods for state updates
  - [ ] Remove scattered state mutations from views

### Testing Checkpoint 4
- [ ] Verify all keyboard shortcuts still work
- [ ] Verify context menu actions work
- [ ] Verify navigation (arrows, focus mode) works
- [ ] Verify state changes are consistent

## Phase 5: Ensure Data Consistency
**Goal**: Maintain invariants between allNodes and nodeChildren

### Tasks
- [ ] Create invariant enforcement helpers
  - [ ] `mergeChildrenIntoNodes()` - ensure children exist in allNodes
  - [ ] `removeStaleChildren()` - clean up deleted nodes
  - [ ] `validateNodeConsistency()` - debug helper to check invariants
- [ ] Use helpers in all update paths
  - [ ] After API responses
  - [ ] After optimistic updates
  - [ ] After partial refreshes
- [ ] Add retry logic for eventual consistency
  - [ ] Template instantiation: retry once if node not found
  - [ ] Node creation: verify node appears in response

### Testing Checkpoint 5
- [ ] Verify node tree remains consistent after operations
- [ ] Verify deleted nodes don't appear in UI
- [ ] Verify new nodes appear immediately
- [ ] Verify parent-child relationships are maintained

## Phase 6: Clean Up and Document
**Goal**: Remove dead code, improve logging, update documentation

### Tasks
- [ ] Remove duplicate refresh implementations
- [ ] Standardize logging (reduce chattiness, consistent categories)
- [ ] Update CLAUDE.md with new architecture
- [ ] Add architecture diagram to docs
- [ ] Write tests for critical paths

### Final Testing Checkpoint
- [ ] Full regression test of all features
- [ ] Performance test with large node trees
- [ ] Offline mode testing
- [ ] Multi-tab testing (macOS)

## Items from Review to Skip/Modify

### Valid but Lower Priority
- **Logging hygiene**: While logs are chatty, they're valuable for debugging. Can reduce later.
- **Testing focus**: Good suggestion but not blocking refactor. Add tests after architecture is fixed.

### Already Handled or Incorrect
- **"refreshNodeChildren only updates nodeChildren"**: The review missed that it DOES update allNodes via updateNodesFromDataManager
- **"Template instantiation bypasses DataManager"**: Partially true, but the real issue is the API call location, not the data flow

## Success Criteria
1. No direct APIClient calls in Features module
2. Single source of truth (DataManager.nodes)
3. Predictable refresh behavior
4. Centralized action handling
5. Maintained data consistency
6. All existing features still work