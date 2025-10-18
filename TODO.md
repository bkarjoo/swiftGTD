# TODO - SwiftGTD

## Drag & Drop Implementation

**Current State**: ✅ **COMPLETED** - Full drag and drop functionality is working including sibling reordering, parent changes, and position-specific drops.

### Implementation Steps

#### 1. Drop Inside Node (Make Child) ✅
- [x] When dropping on a node (80% middle zone), set the dragged node's parent to the target node
- [x] Validation rules:
  - [x] Do not allow dropping inside notes (`nodeType == "note"`)
  - [x] Do not allow dropping inside smart folders (`nodeType == "smart_folder"`)
  - [x] Do not allow dropping on self (prevent circular references)
- [x] API call: Update the node's `parentId` field
- [x] UI update: Move node to new parent's children list

#### 2. Drop Inside Open Node at Specific Position ✅
- [x] When an expanded node shows its children, allow dropping between children
- [x] Set the dragged node's parent to that expanded parent node
- [x] Set the sort_order based on the drop position between children
- [x] Enforce all validation rules from Step 1
- [x] API call: Update both `parentId` and use `reorderNodes` for proper positioning
- [x] UI update: Insert node at the specific position in children list

#### 3. Drop on Node Outside Current Parent ✅
- [x] When dragging from one parent to a different parent's node
- [x] Works exactly like Step 1 (make it a child of the target)
- [x] Handles moving from root level to nested and vice versa
- [x] Maintains all validation rules

#### 4. Drop Outside Open Node at Specific Position ✅
- [x] When dropping at a position outside an expanded node's children
- [x] Detects the parent context (could be root or another parent)
- [x] Sets appropriate parent and sort_order
- [x] Works like Step 2 but for external drops
- [x] Maintains all validation rules

### Technical Implementation Notes

**Drop Zone Detection** (✅ Completed):
- Top 10% (min 8pt) = Drop above as sibling
- Middle 80% = Drop inside as child (blue highlight)
- Bottom 10% (min 8pt) = Drop below as sibling

**Visual Feedback System** (✅ Completed):
- Blue highlight for "drop inside"
- Blue line above/below for sibling drops
- Drag preview with icon and title

**API Integration Required**:
- `PATCH /nodes/{id}` to update `parentId` and `sort_order`
- Refresh affected parent nodes after move
- Handle optimistic updates with rollback on failure

**Edge Cases to Handle**:
- Prevent moving a parent into its own child (circular reference)
- Handle moving nodes with children (move entire subtree)
- Preserve expanded/collapsed state after move
- Update focus/selection appropriately after move

## Other Features

### Keyboard Shortcuts
- [ ] **Cmd+Up Arrow**: Move node up in list
  - Within same parent: swap with previous sibling
  - First child of parent: move out to become sibling of parent (above parent)
  - In focus mode at top: no effect
- [ ] **Cmd+Down Arrow**: Move node down in list
  - Within same parent: swap with next sibling
  - Last child of parent: move out to become sibling of parent (below parent)
  - In focus mode at bottom: no effect
- [ ] Add Cmd+Z for undo last operation
- [ ] Add Cmd+Shift+Z for redo

### Performance
- [ ] Investigate lazy loading for large node trees
- [ ] Add virtual scrolling for better performance with many nodes

### UI Improvements
- [ ] Add animation for node moves
- [ ] Improve drag preview appearance
- [ ] Add multi-select support for bulk operations