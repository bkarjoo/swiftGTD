# SwiftGTD

A native iOS and macOS GTD (Getting Things Done) app built with SwiftUI, designed to work with your existing GTD backend.

## Features

- ✅ Task management with projects, areas, and folders
- 🏷️ Tag system for organization
- 📁 Smart folders with custom rules
- 📝 Note nodes with markdown support
- 📋 Templates for recurring workflows
- 🔐 User authentication
- 📱 Native iOS and macOS experience with SwiftUI
- ⌨️ Comprehensive keyboard shortcuts (macOS)
- 🌙 Dark mode support
- 🔄 Real-time sync with backend API
- 💾 Offline support with sync queue

## Setup

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ / macOS 14.0+ deployment target
- Swift 5.9+
- Your GTD backend running (see backend repo for setup)

### Installation

1. Clone the repository
2. Configure your API endpoint:
   ```bash
   cp Config.xcconfig.example Config.xcconfig
   # Edit Config.xcconfig with your API URL
   ```
3. Open `SwiftGTD.xcodeproj` in Xcode
4. Configure Xcode to use the config file (see CONFIG_SETUP.md for details)
5. Select your development team in the project settings
6. Build and run on your device or simulator

### Backend Connection

The app connects to your GTD backend via the URL configured in `Config.xcconfig`. See CONFIG_SETUP.md for configuration details.

## Architecture

- **SwiftUI**: Modern declarative UI framework
- **MVVM Pattern**: ViewModels manage state and business logic
- **Async/Await**: Modern Swift concurrency for API calls
- **Package-based Modules**: Clean separation of concerns
- **Offline-first**: CacheManager and OfflineQueueManager for resilient sync

## Project Structure

```
SwiftGTD/
├── Packages/Sources/
│   ├── Core/           # Shared utilities, theme, icons, configuration
│   ├── Models/         # Data models (Node, Tag, User, Rules)
│   ├── Networking/     # API client and endpoints
│   ├── Services/       # Business logic (Auth, Data, Cache, Offline)
│   └── Features/       # UI views and view models
├── SwiftGTD/           # iOS app target
├── SwiftGTD-macOS/     # macOS app target
└── docs/               # Documentation and standards
```

## Development Environment

### Build Scripts

The project includes convenient rebuild scripts for quick development cycles:

- **`rebuild_iOS.sh`** - Clean, build, and run on iOS simulator
  ```bash
  ./rebuild_iOS.sh [bundle_id] [simulator_id]
  # Default bundle ID: com.behrooz.SwiftGTD1
  ```

- **`rebuild_macOS.sh`** - Clean, build, and run the macOS app
  ```bash
  ./rebuild_macOS.sh
  ```

### Quick Commands

```bash
# iOS development
./rebuild_iOS.sh                    # Uses default bundle ID and auto-detects simulator
./rebuild_iOS.sh com.your.bundle    # Custom bundle ID
./rebuild_iOS.sh --help             # Show usage

# macOS development
./rebuild_macOS.sh                  # Build and run macOS app
```

### Logging

Comprehensive logging is built into the app for debugging:
- iOS logs: `~/Library/Developer/CoreSimulator/.../Logs/swiftgtd.log`
- macOS logs: `~/Library/Containers/com.swiftgtd.SwiftGTD-macOS/.../Logs/swiftgtd.log`

See CODING_STANDARDS.md for logging requirements and patterns.

## Keyboard Shortcuts (macOS)

### Navigation
- **↑/↓** - Navigate between nodes
- **←** - Collapse node or move to parent
- **→** - Expand node or focus

### Actions
- **⌘D** - Show node details
- **⌘F** - Focus on selected node
- **⌘T** - Manage tags
- **⌘E** - Execute smart folder rule
- **⌘U** - Use template
- **⌘⇧D** - Delete node
- **.** (dot) - Toggle task completion
- **H** - Show help window

### Editing
- **Space** - Quick toggle task/rename node
- **Return** - Edit node title

## Documentation

### Core Documentation
- [**CODING_STANDARDS.md**](docs/CODING_STANDARDS.md) - Development standards, logging requirements, module structure
- [**CONFIG_SETUP.md**](CONFIG_SETUP.md) - Configuration file setup for API endpoints
- [**API_REFERENCE.md**](docs/API_REFERENCE.md) - Complete API endpoint and data model reference
- [**TODO.md**](TODO.md) - Current development tasks and issues

### Feature Documentation
- [**SMART_FOLDERS_IMPLEMENTATION.md**](docs/SMART_FOLDERS_IMPLEMENTATION.md) - Smart folder architecture and rules
- [**OFFLINE_OPTIMISTIC_UPDATES.md**](docs/OFFLINE_OPTIMISTIC_UPDATES.md) - Offline sync and optimistic update system

### Testing Documentation
- [**TEST_PHASES_SUMMARY.md**](docs/testing/TEST_PHASES_SUMMARY.md) - Overview of test suite development
- [**KNOWN_ISSUES.md**](docs/testing/KNOWN_ISSUES.md) - Known test issues and workarounds

## Contributing

1. Read [CODING_STANDARDS.md](docs/CODING_STANDARDS.md) before contributing
2. Follow the logging requirements for all new code
3. Add tests for new features
4. Update documentation as needed

## Support

For issues or questions:
- Check the [Known Issues](docs/testing/KNOWN_ISSUES.md) document
- Review the [API Reference](docs/API_REFERENCE.md) for backend integration
- Create an issue on GitHub

## License

MIT