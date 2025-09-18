# NetworkMonitor Factory Pattern

## Overview

The NetworkMonitor Factory provides a flexible way to switch between real and testable network monitoring implementations. This is particularly useful for:

- **SwiftUI Previews**: Simulate different network conditions
- **UI Testing**: Control network state deterministically  
- **Development**: Toggle offline mode without disabling network
- **Unit Testing**: Inject mock monitors for predictable behavior

## Architecture

```
NetworkMonitorProtocol
    ├── NetworkMonitor (Production - uses real NWPathMonitor)
    └── TestableNetworkMonitor (Testing - fully controllable)

NetworkMonitorFactory
    ├── Environment.production → NetworkMonitor.shared
    ├── Environment.preview → TestableNetworkMonitor (WiFi default)
    ├── Environment.testing → TestableNetworkMonitor (clean state)
    └── Environment.development → TestableNetworkMonitor (configurable)
```

## Usage

### 1. Basic Factory Usage

```swift
// Get the appropriate monitor based on current environment
let monitor = NetworkMonitorFactory.shared

// Configure for specific environment
NetworkMonitorFactory.configure(environment: .preview)

// Reset to production
NetworkMonitorFactory.reset()
```

### 2. SwiftUI Preview Helpers

```swift
struct MyView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MyView()
                .withNetworkPreview(.wifi)
                .previewDisplayName("WiFi")
            
            MyView()
                .withCellularPreview(isExpensive: true)
                .previewDisplayName("Cellular")
            
            MyView()
                .withOfflinePreview()
                .previewDisplayName("Offline")
            
            MyView()
                .withNetworkPreview(.wifi, isConstrained: true)
                .previewDisplayName("Constrained")
        }
    }
}
```

### 3. Development Mode Toggle

Add to your Settings view:

```swift
struct SettingsView: View {
    var body: some View {
        Form {
            DevelopmentNetworkSettings()
            // Other settings...
        }
    }
}
```

This provides a UI toggle for simulating offline mode during development.

### 4. App Initialization

In your App file or AppDelegate:

```swift
@main
struct SwiftGTDApp: App {
    init() {
        #if DEBUG
        NetworkMonitorFactory.initializeForCurrentEnvironment()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 5. Dependency Injection in DataManager

DataManager now accepts an optional NetworkMonitor:

```swift
// Production (uses factory default)
let dataManager = DataManager()

// Testing with specific monitor
let testMonitor = TestableNetworkMonitor()
testMonitor.simulateConnectionChange(isConnected: false)
let dataManager = DataManager(networkMonitor: testMonitor)
```

## Environment Detection

The factory automatically detects:

- **Preview Mode**: `ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"`
- **UI Testing**: `CommandLine.arguments.contains("--uitesting")`
- **Development Offline**: `UserDefaults.standard.bool(forKey: kDevelopmentModeOfflineKey)`

## Testing Patterns

### Unit Tests

```swift
func testDataManager_whenOffline_queuesOperations() async {
    // Arrange
    let monitor = TestableNetworkMonitor()
    monitor.simulateConnectionChange(isConnected: false)
    let dataManager = DataManager(networkMonitor: monitor)
    
    // Act
    await dataManager.createNode(...)
    
    // Assert
    XCTAssertFalse(dataManager.offlineQueue.isEmpty)
}
```

### UI Tests

```swift
func testOfflineBehavior() {
    // Launch app with testing environment
    let app = XCUIApplication()
    app.launchArguments.append("--uitesting")
    app.launch()
    
    // Factory will use TestableNetworkMonitor
    // Control network state via test helpers
}
```

### Integration Tests

```swift
func testNetworkStateTransitions() async {
    // Arrange
    let monitor = TestableNetworkMonitor()
    let dataManager = DataManager(networkMonitor: monitor)
    
    // Act - Simulate network changes
    monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
    // ... perform operations
    monitor.simulateConnectionChange(isConnected: false)
    // ... verify offline behavior
    monitor.simulateConnectionChange(isConnected: true, connectionType: .cellular)
    // ... verify sync behavior
}
```

## Future Phase 20 Testing

As suggested in the review, Phase 20 will test Combine publisher behavior:

```swift
func testNetworkMonitor_publisherUpdates_notifySubscribers() async {
    // Arrange
    let monitor = TestableNetworkMonitor()
    let expectation = XCTestExpectation(description: "Publisher update")
    
    var receivedStates: [Bool] = []
    let cancellable = monitor.$isConnected
        .sink { isConnected in
            receivedStates.append(isConnected)
            if receivedStates.count == 3 {
                expectation.fulfill()
            }
        }
    
    // Act
    monitor.simulateConnectionChange(isConnected: false)
    monitor.simulateConnectionChange(isConnected: true, connectionType: .wifi)
    monitor.simulateConnectionChange(isConnected: false)
    
    // Assert
    await fulfillment(of: [expectation], timeout: 1.0)
    XCTAssertEqual(receivedStates, [true, false, true, false])
}
```

## Benefits

1. **Deterministic Testing**: No dependency on actual network conditions
2. **Preview Flexibility**: See UI in different network states instantly
3. **Development Efficiency**: Toggle offline mode without airplane mode
4. **Test Coverage**: Can test all network scenarios reliably
5. **Production Safety**: Factory only affects DEBUG builds
6. **Clean Separation**: All Phase 20 tests run against TestableNetworkMonitor - no production code changes needed beyond Phase 19's DI
7. **Non-invasive Logging**: Test logs use "[TEST]" prefix and don't affect test assertions

## Test Architecture Highlights

### Clean Separation
- **Phase 19**: Introduced DI infrastructure (protocols, factory, TestableNetworkMonitor)
- **Phase 20**: All 19 tests run against TestableNetworkMonitor
- **Production Code**: Remains untouched after Phase 19
- **Test Isolation**: No coupling between test infrastructure and production implementation

### Non-Invasive Testing
```swift
// Test logs are clearly marked
ℹ️ INFO [TestableNetworkMonitor] ✅ [TEST] Network connected (Wi-Fi)
ℹ️ INFO [TestableNetworkMonitor] ❌ [TEST] Network disconnected

// Production logs remain clean
ℹ️ INFO [NetworkMonitor] ✅ Network connected (Wi-Fi)
ℹ️ INFO [NetworkMonitor] ❌ Network disconnected
```

## Implementation Checklist

- [x] NetworkMonitorProtocol for abstraction
- [x] TestableNetworkMonitor implementation
- [x] NetworkMonitorFactory with environments
- [x] SwiftUI preview modifiers
- [x] Development mode toggle
- [x] DataManager dependency injection
- [x] Preview examples
- [x] Phase 20: Combine publisher tests (completed)
- [ ] Phase 21+: CacheManager integration tests

## Notes

- The factory pattern keeps production code clean while enabling testing
- All test-related code is wrapped in `#if DEBUG` to avoid shipping test code
- The pattern is extensible - new environments can be added easily
- TestableNetworkMonitor maintains API compatibility with NetworkMonitor