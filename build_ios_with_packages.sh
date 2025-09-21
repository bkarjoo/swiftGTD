#!/bin/bash

echo "📱 Building iOS app with packages..."

# Clean previous builds
echo "🧹 Cleaning..."
rm -rf ~/Library/Developer/Xcode/DerivedData/SwiftGTD-*

# Build using xcodebuild with proper scheme and configuration
echo "🔨 Building iOS app..."
xcodebuild \
    -project SwiftGTD.xcodeproj \
    -scheme SwiftGTD \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | while IFS= read -r line; do
        # Show progress but filter out noise
        if echo "$line" | grep -E "(Building|Compiling|Linking|Processing|Copying|▸|warning:|error:|BUILD|FAILED|Succeeded)" > /dev/null; then
            echo "$line"
        fi
    done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded"

    # Find the built app
    APP_PATH=$(find build -name "SwiftGTD.app" -type d | head -1)

    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find built app"
        exit 1
    fi

    echo "📦 Found app at: $APP_PATH"

    # Get a booted simulator
    SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 15" | grep "(Booted)" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)

    if [ -z "$SIMULATOR_ID" ]; then
        echo "📱 Booting iPhone 15 simulator..."
        # Get any iPhone 15
        SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 15" | head -1 | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')

        if [ -n "$SIMULATOR_ID" ]; then
            open -a Simulator
            xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
            sleep 3
        else
            echo "❌ No iPhone 15 simulator found"
            exit 1
        fi
    fi

    echo "📲 Installing app on simulator: $SIMULATOR_ID"
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