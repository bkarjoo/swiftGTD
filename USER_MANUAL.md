# SwiftGTD User Manual

Welcome to SwiftGTD - your powerful task management system inspired by the Getting Things Done (GTD) methodology. This manual will help you master all features and keyboard shortcuts to boost your productivity.

## Table of Contents
- [Getting Started](#getting-started)
- [Core Concepts](#core-concepts)
- [Navigation](#navigation)
- [Node Types](#node-types)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Working with Nodes](#working-with-nodes)
- [Focus Mode](#focus-mode)
- [Smart Folders](#smart-folders)
- [Templates](#templates)
- [Tags](#tags)
- [Tabs](#tabs)
- [Search and Filter](#search-and-filter)
- [Sync and Offline Mode](#sync-and-offline-mode)
- [Tips and Best Practices](#tips-and-best-practices)

## Getting Started

### First Login
1. Launch SwiftGTD
2. Enter your email and password
3. Check "Remember Me" to stay logged in across sessions
4. Click "Log In" or press Enter

### Creating Your First Task
1. Press `T` to create a new task
2. Type your task name
3. Press Enter to save
4. Your task appears in the tree view

## Core Concepts

SwiftGTD uses a **hierarchical tree structure** to organize your work:

- **Nodes**: The basic building blocks (tasks, folders, notes, etc.)
- **Tree View**: Visual hierarchy showing parent-child relationships
- **Focus Mode**: Zoom into any node to see only its contents
- **Selection vs Focus**: Selection (gray highlight) is what you're working on; Focus is your current view scope

## Navigation

### Mouse Navigation
- **Click node title**: Focus on that node
- **Click chevron (▶)**: Expand/collapse children
- **Click icon**: Toggle task completion or expand/collapse
- **Right-click**: Open context menu with actions
- **Drag & Drop**: Reorder sibling nodes

### Keyboard Navigation
- **↑/↓ Arrow**: Move selection up/down
- **←/→ Arrow**: Collapse/expand nodes or navigate focus
- **Enter**: Rename selected node
- **Space**: Toggle task completion

### Arrow Key Behavior
- **Right Arrow** on expanded folder: Focus on it (zoom in)
- **Right Arrow** on collapsed folder: Expand it
- **Right Arrow** on note: Open note editor
- **Left Arrow** on expanded folder: Collapse it
- **Left Arrow** when focused: Move focus to parent
- **Left Arrow** on collapsed folder: Move selection to parent

## Node Types

### 📁 Folder
Organize related items together. Can contain any other node types.

### ✓ Task
Actionable items with completion status. Click checkbox or press Space to toggle.

### 📝 Note
Rich text documents for reference information. Click to open editor.

### ⭐ Project
Special folder for multi-step outcomes. Tracks overall progress.

### 📥 Area
Ongoing responsibility areas that don't have an end date.

### ✨ Smart Folder
Dynamic folders that show items matching specific criteria.

### 📄 Template
Reusable structures. Press `Cmd+U` to instantiate.

## Keyboard Shortcuts

### Navigation
| Shortcut | Action |
|----------|--------|
| `↑/↓` | Navigate up/down |
| `←/→` | Collapse/expand or change focus |
| `Cmd+↑` | Jump to first item |
| `Cmd+↓` | Jump to last item |
| `Tab` | Next tab |
| `Shift+Tab` | Previous tab |

### Creation
| Shortcut | Action |
|----------|--------|
| `F` | New folder |
| `T` | New task |
| `N` | New note |
| `Cmd+N` | Generic create dialog |
| `Cmd+T` | New tab |

### Editing
| Shortcut | Action |
|----------|--------|
| `Enter` | Rename node |
| `Escape` | Cancel editing |
| `Delete` | Delete selected node |
| `Cmd+Shift+D` | Delete with confirmation |

### Actions
| Shortcut | Action |
|----------|--------|
| `Space` or `.` | Toggle task completion |
| `Cmd+Enter` | Open note editor |
| `Cmd+D` | Show node details |
| `Cmd+Shift+F` | Focus on node |
| `Cmd+T` | Manage tags |
| `Cmd+E` | Execute smart folder |
| `Cmd+U` | Use template |
| `Cmd+K` | Copy node names |
| `Cmd+?` | Show keyboard shortcuts help |

### Tabs
| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab |
| `Cmd+1-9` | Switch to tab 1-9 |
| `Tab` | Next tab |
| `Shift+Tab` | Previous tab |

## Working with Nodes

### Creating Nodes
1. Select parent location
2. Press appropriate shortcut (`F`, `T`, `N`)
3. Enter name
4. Press Enter to create

### Renaming Nodes
1. Select the node
2. Press `Enter` or click to edit
3. Type new name
4. Press `Enter` to save or `Escape` to cancel

### Deleting Nodes
1. Select the node
2. Press `Delete` or `Cmd+Shift+D`
3. Confirm deletion (deletes node and all children)

### Moving Nodes
- **Drag & Drop**: Click and drag to reorder siblings
- Nodes can only be reordered within the same parent
- Drop indicator shows where node will be placed

## Focus Mode

Focus mode lets you "zoom into" any node to work with just that branch:

### Entering Focus Mode
- **Mouse**: Click on node title
- **Keyboard**: Select node and press `Cmd+Shift+F`
- **Right Arrow**: On an expanded folder

### In Focus Mode
- Breadcrumb trail shows your location
- Only the focused node and its children are visible
- All navigation is constrained to this branch

### Exiting Focus Mode
- **Click** "All Nodes" in breadcrumb
- **Left Arrow** when focused node is selected
- **Click** any parent in breadcrumb trail

## Smart Folders

Smart folders dynamically show nodes matching specific criteria:

### Using Smart Folders
1. Click or navigate to a smart folder
2. It automatically executes and shows matching items
3. Results update when underlying data changes

### Smart Folder Types
- **All Tasks**: Shows all incomplete tasks
- **Today**: Items due today
- **Upcoming**: Items due in the next 7 days
- **Someday**: Items tagged for future consideration
- **Custom**: User-defined criteria

## Templates

Templates are reusable node structures:

### Creating from Template
1. Select a template node
2. Press `Cmd+U` or right-click → "Use Template"
3. Template structure is copied to current location
4. Edit the new instance as needed

### Common Templates
- **Weekly Review**: Checklist for GTD weekly review
- **Project Template**: Standard project structure
- **Meeting Notes**: Formatted meeting template

## Tags

Organize nodes across the hierarchy with tags:

### Adding Tags
1. Select a node
2. Press `Cmd+T` or right-click → "Tags"
3. Select tags from the picker
4. Click "Done"

### Tag Features
- Multiple tags per node
- Color-coded for quick identification
- First 2 tags shown inline, "+N" for additional
- Smart folders can filter by tags

## Tabs

Work with multiple views simultaneously:

### Tab Management
- **Create**: `Cmd+T` or click "+" button
- **Close**: `Cmd+W` or click "×" on tab
- **Switch**: Click tab or use `Cmd+1-9`
- **Rename**: Double-click tab name

### Tab Features
- Each tab maintains its own:
  - Selected node
  - Focus state
  - Expanded/collapsed states
- Tabs persist across sessions
- Maximum 9 tabs supported

## Search and Filter

### Quick Search
1. Press `Cmd+F` (if implemented)
2. Type search terms
3. Results update in real-time
4. Press Escape to clear

### Filtering
- Use smart folders for predefined filters
- Create custom smart folders for frequent searches
- Tags provide cross-cutting organization

## Sync and Offline Mode

### Online Mode
- Changes sync automatically to server
- Green indicator shows connection status
- Real-time updates across devices

### Offline Mode
- Continue working without internet
- Changes queue locally
- Orange indicator shows offline status
- Automatic sync when connection returns

### Sync Status Indicators
- **Green circle**: Connected and synced
- **Orange circle**: Offline mode
- **Red circle**: Sync error (check connection)
- **Spinner**: Sync in progress

## Tips and Best Practices

### GTD Workflow
1. **Capture**: Use quick task creation (`T`) to capture everything
2. **Clarify**: Add details, due dates, and tags during processing
3. **Organize**: Use folders and projects to structure work
4. **Reflect**: Regular reviews using smart folders
5. **Engage**: Focus mode for distraction-free work

### Productivity Tips
- Use **Focus Mode** to reduce overwhelm
- Create **Templates** for recurring workflows
- **Smart Folders** for dynamic lists (Today, This Week)
- **Multiple Tabs** for different contexts (Work, Personal)
- **Keyboard shortcuts** for speed

### Organization Strategies
- **Areas** for ongoing responsibilities
- **Projects** for multi-step outcomes
- **Single tasks** in appropriate context folders
- **Notes** for reference material
- **Tags** for cross-cutting concerns (#waiting, #urgent)

### Daily Workflow
1. **Morning**: Review "Today" smart folder
2. **Capture**: Add new items as they arise (`T`)
3. **Process**: Clarify and organize during breaks
4. **Focus**: Use focus mode for deep work
5. **Evening**: Quick review and planning for tomorrow

### Weekly Review
1. Clear inbox (unfiled items)
2. Review project progress
3. Update due dates
4. Archive completed projects
5. Plan upcoming week

## Troubleshooting

### Can't see all nodes?
- Check if you're in Focus Mode (look for breadcrumb)
- Verify nodes aren't collapsed (look for chevron)

### Changes not saving?
- Check sync status indicator
- Ensure you're logged in
- Try manual refresh (`Cmd+R` if available)

### Keyboard shortcuts not working?
- Ensure a node is selected
- Check you're not in edit mode
- Some shortcuts require specific node types

### Performance issues?
- Large trees may take time to load
- Use Focus Mode to work with smaller sets
- Close unused tabs

## Need Help?

- **In-app help**: Press `Cmd+?` for keyboard shortcuts
- **Report issues**: [GitHub Issues](https://github.com/anthropics/claude-code/issues)
- **Updates**: Check for app updates regularly

---

*SwiftGTD - Making GTD Swift and Simple*