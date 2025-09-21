#!/bin/bash

# Rebuild iOS app without code signing

echo "📱 Building iOS app (unsigned)..."

# Clean build folder first
echo "🧹 Cleaning build folder..."
rm -rf build

# Build for iOS Simulator
echo "🔨 Building for iOS Simulator..."
xcodebuild \
    -project SwiftGTD.xcodeproj \
    -target SwiftGTD \
    -configuration Debug \
    -sdk iphonesimulator \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    clean build

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded"

    # Find the built app
    BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData"
    APP_PATH=$(find "$BUILD_DIR" -name "SwiftGTD.app" -path "*/Debug-iphonesimulator/*" -type d | head -1)

    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find built app"
        exit 1
    fi

    echo "📦 Found app at: $APP_PATH"

    # Check if any simulator exists
    echo "🔍 Checking for available simulators..."
    SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone.*\(" | head -1 | grep -o "[A-F0-9]\{8\}-[A-F0-9]\{4\}-[A-F0-9]\{4\}-[A-F0-9]\{4\}-[A-F0-9]\{12\}")

    if [ -z "$SIMULATOR_ID" ]; then
        echo "📱 No iPhone simulator found. Creating one..."
        SIMULATOR_ID=$(xcrun simctl create "iPhone 15" "com.apple.CoreSimulator.SimDeviceType.iPhone-15" "com.apple.CoreSimulator.SimRuntime.iOS-18-6")
    fi

    echo "📱 Using simulator ID: $SIMULATOR_ID"

    # Open the Simulator
    echo "🚀 Opening iOS Simulator..."
    open -a Simulator

    # Boot the simulator if needed
    echo "🔌 Booting simulator..."
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true

    # Wait a moment for simulator to be ready
    sleep 3

    # Install the app
    echo "📲 Installing app on simulator..."
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

    # Get the bundle identifier
    BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || echo "com.swiftgtd.app")
    echo "📦 Bundle ID: $BUNDLE_ID"

    # Launch the app
    echo "🚀 Launching app..."
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

    echo "✨ App launched successfully!"
else
    echo "❌ Build failed"
    exit 1
fi