#!/bin/bash

echo "SwiftGTD macOS Rebuild Script"
echo "=============================="

# Get bundle ID from parameter or use default
BUNDLE_ID="${1:-com.swiftgtd.SwiftGTD-macOS}"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [bundle_id]"
    echo "Default bundle ID: com.swiftgtd.SwiftGTD-macOS"
    exit 0
fi

echo "Using bundle ID: $BUNDLE_ID"

# Clear all log directories for a fresh start
if [ "$2" != "--keep-logs" ]; then
    echo "Clearing all log directories..."
    # iOS Simulator logs
    rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Application\ Support/Logs/ 2>/dev/null
    # Non-containerized macOS logs
    rm -rf ~/Library/Application\ Support/Logs/SwiftGTD/ 2>/dev/null
    # Containerized macOS app logs (the actual location for sandboxed macOS apps)
    rm -rf ~/Library/Containers/com.swiftgtd.SwiftGTD-macOS/Data/Library/Application\ Support/Logs/ 2>/dev/null
    echo "✅ Log directories cleared"
else
    echo "Keeping existing logs (--keep-logs flag set)"
fi

# Clean build
echo "Cleaning build..."
xcodebuild clean -project SwiftGTD.xcodeproj -scheme SwiftGTD-macOS -destination "platform=macOS" > /dev/null 2>&1

# Build the app
echo "Building SwiftGTD for macOS..."
xcodebuild build -project SwiftGTD.xcodeproj -scheme SwiftGTD-macOS -destination "platform=macOS" -quiet

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful"

# Kill existing app if running
echo "Stopping any existing instances..."
pkill -f "SwiftGTD-macOS" 2>/dev/null || true

# Find the built app
APP_PATH="/Users/behroozkarjoo/Library/Developer/Xcode/DerivedData/SwiftGTD-hbzedynpmvxtyretxxqxzebhjewe/Build/Products/Debug/SwiftGTD-macOS.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at: $APP_PATH"
    echo "Looking for app..."
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SwiftGTD-macOS.app" -type d | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find SwiftGTD-macOS.app"
        exit 1
    fi
fi

echo "Using app at: $APP_PATH"

# Launch the app
echo "Launching SwiftGTD for macOS..."
open "$APP_PATH" 2>&1

# Check if app actually launched regardless of open command exit code
sleep 2
if pgrep -f "SwiftGTD-macOS" > /dev/null; then
    echo "✅ App launched!"
    echo ""
    echo "To view logs:"
    echo "  Console.app → Search for 'SwiftGTD'"
else
    echo "⚠️  App may not have launched properly. Trying direct execution..."
    "$APP_PATH/Contents/MacOS/SwiftGTD-macOS" &
    sleep 2
    if pgrep -f "SwiftGTD-macOS" > /dev/null; then
        echo "✅ App launched via direct execution!"
    else
        echo "❌ Failed to launch app"
        exit 1
    fi
fi