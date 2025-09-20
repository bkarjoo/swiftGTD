#!/bin/bash

# Rebuild iOS app without code signing

echo "📱 Building iOS app (unsigned)..."

# First, check if iPhone 16 simulator exists
echo "🔍 Checking for iPhone 16 simulator..."
SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 16 (" | head -1 | grep -o "[A-F0-9]\{8\}-[A-F0-9]\{4\}-[A-F0-9]\{4\}-[A-F0-9]\{4\}-[A-F0-9]\{12\}")

if [ -z "$SIMULATOR_ID" ]; then
    echo "📱 Creating iPhone 16 simulator..."
    SIMULATOR_ID=$(xcrun simctl create "iPhone 16" "com.apple.CoreSimulator.SimDeviceType.iPhone-16" "com.apple.CoreSimulator.SimRuntime.iOS-18-6")
    echo "✅ Created simulator with ID: $SIMULATOR_ID"
fi

SIMULATOR_NAME="iPhone 16"
echo "📱 Using simulator: $SIMULATOR_NAME (ID: $SIMULATOR_ID)"

# Build for generic iOS simulator to avoid specific device issues
echo "🔨 Building for iOS Simulator..."
xcodebuild -scheme SwiftGTD \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    build 2>&1 | while IFS= read -r line; do
        # Show progress but filter out noise
        if echo "$line" | grep -E "(Building|Compiling|Linking|Processing|Copying|▸|warning:|error:|BUILD|FAILED)" > /dev/null; then
            echo "$line"
        fi
    done

# Check if build succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded"

    # Find the built app
    APP_PATH=$(find build -name "SwiftGTD.app" -type d | head -1)

    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find built app"
        exit 1
    fi

    echo "📦 Found app at: $APP_PATH"

    # Open the Simulator
    echo "🚀 Opening iOS Simulator..."
    open -a Simulator

    # Boot the simulator if needed
    echo "🔌 Booting simulator..."
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true

    # Wait for simulator to be ready
    echo "⏳ Waiting for simulator to boot..."
    xcrun simctl bootstatus "$SIMULATOR_ID" -b

    # Get the bundle identifier from the app
    BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || echo "com.behrooz.SwiftGTD1")
    echo "📦 Bundle ID: $BUNDLE_ID"

    # Install the app
    echo "📲 Installing app on simulator..."
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

    # Launch the app
    echo "🚀 Launching app..."
    xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

    echo "✨ App launched successfully!"
else
    echo "❌ Build failed"
    exit 1
fi