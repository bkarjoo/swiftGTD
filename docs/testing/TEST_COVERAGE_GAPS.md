# Test Coverage Gaps

## Recent Features Needing Tests

### 1. Keyboard Shortcuts (TreeView_macOS)
**Priority: HIGH**
- [ ] Arrow key navigation (up/down/left/right)
- [ ] Command+D (Show details)
- [ ] Command+F (Focus mode)
- [ ] Command+T (Tag management)
- [ ] Command+E (Execute smart folder)
- [ ] Command+U (Use template)
- [ ] Command+Shift+D (Delete)
- [ ] Dot key (Toggle task)
- [ ] Space key (Quick edit)
- [ ] Return key (Edit title)
- [ ] Escape key (Cancel edit)

### 2. Tag Management
**Priority: HIGH**
- [ ] Tag picker view functionality
- [ ] Attach tag to node
- [ ] Detach tag from node
- [ ] Tag search functionality
- [ ] Tag creation from picker
- [ ] Tags not resetting unsaved changes (reloadTagsOnly)

### 3. Node Details View
**Priority: HIGH**
- [ ] Parent change moves selection
- [ ] Save button always enabled
- [ ] Sort order changes
- [ ] Task field updates
- [ ] Note body updates
- [ ] Template field updates
- [ ] Smart folder rule selection
- [ ] Field validation
- [ ] Cancel restores original values

### 4. Smart Folder Features
**Priority: MEDIUM**
- [ ] Execute rule on expand
- [ ] Execute rule on focus
- [ ] Contents caching
- [ ] Smart folder can't be parent
- [ ] Smart folder can't be tagged
- [ ] Rule execution API call

### 5. Template Features
**Priority: MEDIUM**
- [ ] Template instantiation
- [ ] Target node selection
- [ ] Container creation option
- [ ] Template usage tracking

### 6. Note Editor
**Priority: MEDIUM**
- [ ] Markdown editing
- [ ] Auto-save functionality
- [ ] Cancel without saving
- [ ] Note body updates

### 7. Configuration System
**Priority: LOW**
- [ ] Config.xcconfig loading
- [ ] API URL configuration
- [ ] Fallback values
- [ ] Environment-specific configs

### 8. Offline Features Updates
**Priority: HIGH**
- [ ] Tag operations queuing
- [ ] Parent change offline handling
- [ ] Details view offline updates
- [ ] Smart folder offline behavior

### 9. UI State Management
**Priority: MEDIUM**
- [ ] Focus mode state
- [ ] Expanded nodes persistence
- [ ] Selection state management
- [ ] Edit mode transitions

### 10. Navigation Functions
**Priority: HIGH**
- [ ] moveToNextSibling with logging
- [ ] moveToPreviousSibling with logging
- [ ] moveToFirstChild with logging
- [ ] moveToParent with logging
- [ ] findLastVisibleDescendant
- [ ] getSiblings

## Test Implementation Plan

### Phase 1: Critical Path Tests
1. Keyboard shortcuts basic functionality
2. Tag management core operations
3. Node details save/cancel
4. Navigation functions

### Phase 2: Feature Tests
1. Smart folder execution
2. Template instantiation
3. Note editor operations
4. Parent change behavior

### Phase 3: Integration Tests
1. Offline queue with new features
2. Configuration system
3. UI state persistence
4. Complex workflows

## Estimated Test Count
- ~50 new test cases for keyboard shortcuts
- ~30 new test cases for tag management
- ~40 new test cases for details view
- ~20 new test cases for smart folders
- ~15 new test cases for templates
- ~20 new test cases for navigation
- **Total: ~175 new test cases needed**

## Testing Utilities Needed
1. Mock keyboard event generator
2. Mock tag picker delegate
3. Details view test helper
4. Navigation state validator
5. Focus mode test helper