#!/bin/bash

echo "🔨 Building iOS app..."

# Build for iOS Simulator using the correct target
xcodebuild build \
    -project SwiftGTD.xcodeproj \
    -target SwiftGTD \
    -configuration Debug \
    -sdk iphonesimulator \
    ONLY_ACTIVE_ARCH=NO

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded"

    # Find the app
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SwiftGTD.app" -path "*/Debug-iphonesimulator/*" | head -1)

    if [ -n "$APP_PATH" ]; then
        echo "📱 App found at: $APP_PATH"

        # Get a booted simulator
        SIMULATOR_ID=$(xcrun simctl list devices | grep "(Booted)" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)

        if [ -n "$SIMULATOR_ID" ]; then
            echo "Installing on simulator: $SIMULATOR_ID"
            xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

            # Launch
            BUNDLE_ID="com.behrooz.SwiftGTD1"
            xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"
            echo "✅ App launched!"
        else
            echo "❌ No booted simulator found. Boot one first with: open -a Simulator"
        fi
    else
        echo "❌ Could not find built app"
    fi
else
    echo "❌ Build failed"
    exit 1
fi