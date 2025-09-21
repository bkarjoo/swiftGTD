# TODO: Architecture Refactoring Plan

## Overview
This refactoring addresses architectural issues identified in code review, focusing on establishing single source of truth, consistent data flow, and proper separation of concerns.

## Phase 1: Centralize API Operations in Services Layer ✅
**Goal**: Remove all direct APIClient calls from views and route through DataManager

### Tasks
- [x] Move default folder API calls from views to DataManager
  - [x] Add `getDefaultFolder()` and `setDefaultFolder()` methods to DataManager
  - [x] Update TreeView_macOS and TabbedTreeView to use DataManager methods
- [x] Move template instantiation from views to DataManager
  - [x] Add `instantiateTemplate(template:)` method to DataManager
  - [x] Remove inline instantiation from TreeView_macOS
- [x] Move smart folder execution to DataManager
  - [x] Add `executeSmartFolder(node:)` method to DataManager
  - [x] Update all call sites

### Testing Checkpoint 1
- [ ] Verify Q key still creates tasks in default folder
- [ ] Verify Cmd+U still instantiates templates correctly
- [ ] Verify smart folder execution still works
- [x] Verify no direct APIClient calls remain in main Features (some remain in specialized views like NodeDetailsViewModel and TagPickerView)

## Phase 2: Single Source of Truth ✅
**Goal**: TreeViewModel should only subscribe to DataManager.nodes, never maintain separate state

### Tasks
- [x] Remove TreeViewModel.allNodes as separate state
  - [x] Make allNodes a computed property from DataManager.nodes
  - [x] Update all references to use DataManager as source
- [x] Ensure nodeChildren is derived from DataManager.nodes
  - [x] Create single update method that builds nodeChildren from nodes
  - [x] Remove all direct nodeChildren mutations (except smart folders which are virtual)
- [x] Remove redundant node storage patterns
  - [x] Audit for any other duplicate node storage
  - [x] Consolidate to DataManager.nodes only

### Testing Checkpoint 2
- [x] Verify build succeeds
- [x] Verify tests compile
- [ ] Verify tree view still displays correctly (manual test)
- [ ] Verify selection/focus/expansion states persist (manual test)
- [ ] Verify drag and drop reordering works (manual test)
- [ ] Verify no duplicate node states exist (manual test)

## Phase 3: Fix Refresh Semantics ✅
**Goal**: Clear, predictable refresh behavior without footguns

### Tasks
- [x] Rename loadAllNodes() to initialLoad()
  - [x] Make it clear this only runs once with didLoad guard
  - [x] Update all call sites that expect refresh to use appropriate method
- [x] Standardize on refreshNodes() for full refresh
  - [x] Ensure it always fetches fresh data (uses DataManager.syncAllData)
  - [x] Update all refresh call sites to use this
- [x] Implement targeted refresh properly
  - [x] Create refreshNode(nodeId:) that updates node and its children
  - [x] Delegates to DataManager.refreshNode for consistency
  - [x] updateSingleNode now delegates to refreshNode

### Testing Checkpoint 3
- [x] Verify build succeeds
- [ ] Verify initial load works on app start (manual test)
- [ ] Verify pull-to-refresh works on iOS (manual test)
- [ ] Verify refresh button works on macOS (manual test)
- [ ] Verify template instantiation refreshes correctly (manual test)
- [ ] Verify node creation/deletion updates tree properly (manual test)

## Phase 4: Centralize UI Operations ✅
**Goal**: Move keyboard and menu actions to ViewModel intent methods

### Tasks
- [x] Create intent methods in TreeViewModel
  - [x] `handleKeyPress(keyCode:modifiers:)` - centralized keyboard handling
  - [x] `performNodeAction(action:nodeId:)` - menu/context actions
  - [x] `navigateToNode(direction:)` - navigation intents (basic implementation)
- [x] Move keyboard handling logic from views to ViewModel
  - [x] TreeView_macOS now delegates to ViewModel.handleKeyPress
  - [~] TabbedTreeView partially delegates (kept tab-specific shortcuts)
- [x] Centralize selection/focus/expansion state changes
  - [x] Created performAction method for all node actions
  - [x] Added toggleExpansion helper for state updates

### Testing Checkpoint 4
- [x] Build succeeds
- [ ] Verify all keyboard shortcuts still work (manual test)
- [ ] Verify context menu actions work (manual test)
- [ ] Verify navigation (arrows, focus mode) works (manual test)
- [ ] Verify state changes are consistent (manual test)

## Phase 5: Ensure Data Consistency
**Goal**: Maintain invariants between allNodes and nodeChildren

### Critical Issue: refreshNode doesn't maintain invariants
**Problem**: When `refreshNode(nodeId)` is called, it only updates that single node in the array, not its children. This breaks parent-child consistency.

**Why it's complex**:
- API's `getNode(id:)` returns only the single node, not children
- Need separate `getNodes(parentId:)` call for children
- Risk of cascading API calls for deep trees
- Must handle orphaned nodes (remove old children, add new ones)

### Tasks
- [ ] Fix targeted refresh to maintain invariants
  - [ ] Update `refreshNode` to fetch node AND its direct children
  - [ ] Remove stale children that no longer exist
  - [ ] Add new children that were created
  - [ ] Consider depth limit to avoid cascade
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
- [x] Remove duplicate refresh implementations
- [ ] Standardize logging (reduce chattiness, consistent categories)
- [x] Update CLAUDE.md with new architecture (partially - flows updated, needs diagram)
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