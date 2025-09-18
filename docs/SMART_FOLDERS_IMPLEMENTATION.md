# Smart Folders Implementation

## Overview
Smart folders are virtual containers that dynamically display nodes matching specific rules. Unlike regular folders, their contents are determined by executing server-side rules rather than static parent-child relationships.

## Implementation Rules

### Rule 1: No Node Can Make a Smart Folder Its Parent
- **Location**: `NodeDetailsViewModel.swift:186-189`
- **Rationale**: Smart folders are virtual containers with dynamic content
- **Implementation**: Filter out smart folders from available parents list

### Rule 2: Cannot Tag Smart Folders
- **Location**: `TreeNodeView.swift:100-108`
- **Rationale**: Smart folders are virtual containers and don't support tags
- **Implementation**: Hide "Tags" option in context menu for smart folders

### Rule 3: Execute Rule on User Interaction
Smart folders load their contents via API when:
1. **Chevron Click** (`TreeNodeView.swift:184-190`): Expanding via chevron
2. **Title Click** (`TreeNodeView.swift:227-233`): Focusing via title click
3. **Context Menu** (`TreeNodeView.swift:74-83`): "Execute" action

### Rule 4: No Offline Support (Future Work)
- Smart folders require network connectivity to execute rules
- Offline mode will show empty contents for smart folders

## Architecture

### API Endpoint
- **Endpoint**: `/nodes/{smart_folder_id}/contents`
- **Method**: GET
- **Response**: Array of nodes matching the smart folder's rule
- **Implementation**: `NodeEndpoints.swift:executeSmartFolderRule()`

### Data Flow
1. User interaction (click/expand) triggers execution
2. API call to fetch smart folder contents
3. Results stored in `nodeChildren` dictionary
4. Tree view displays children under smart folder
5. Children persist until collapsed or focus changes

### UI Behavior
- Smart folders always show chevron (expandable)
- Context menu shows "Execute" instead of "Details"
- Contents load asynchronously with loading indicator
- Can be collapsed to hide contents
- Contents remain loaded when navigating back from focus mode

## Logging
Comprehensive logging implemented per CODING_STANDARDS.md:
- 🧩 Smart folder interactions
- 📞 API calls and responses
- 📦 Node count and type breakdown
- ❌ Error conditions with full details

## Testing Considerations
When testing smart folders:
1. Verify chevron appears for all smart folders
2. Test expand/collapse behavior
3. Verify API call on first expansion
4. Check that tags menu item is hidden
5. Test focus mode with smart folders
6. Verify error handling for API failures

## Future Enhancements
- [ ] Offline support with cached results
- [ ] Auto-refresh based on `autoRefresh` property
- [ ] Loading state indicator while fetching
- [ ] Refresh button in context menu
- [ ] Rule execution history/logging