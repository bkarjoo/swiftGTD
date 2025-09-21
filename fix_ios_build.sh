#!/bin/bash

echo "📱 Fixing iOS build configuration..."

# Clean everything first
echo "🧹 Cleaning all derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/SwiftGTD-*
rm -rf build

# First, resolve packages
echo "📦 Resolving Swift packages..."
xcodebuild -resolvePackageDependencies -project SwiftGTD.xcodeproj

# Build the packages first for iOS
echo "🔨 Building packages for iOS..."
xcodebuild build \
    -project Packages/SwiftGTDModules.xcodeproj \
    -scheme Core \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build \
    -project Packages/SwiftGTDModules.xcodeproj \
    -scheme Models \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build \
    -project Packages/SwiftGTDModules.xcodeproj \
    -scheme Networking \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build \
    -project Packages/SwiftGTDModules.xcodeproj \
    -scheme Services \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build \
    -project Packages/SwiftGTDModules.xcodeproj \
    -scheme Features \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO

# Now build the iOS app
echo "🔨 Building iOS app..."
xcodebuild build \
    -project SwiftGTD.xcodeproj \
    -scheme SwiftGTD \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath build \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -E "(Building|Compiling|Linking|error:|warning:|BUILD|FAILED|Succeeded)" > /dev/null; then
            echo "$line"
        fi
    done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded!"

    # Find and install the app
    APP_PATH=$(find build -name "SwiftGTD.app" -type d | grep -v "SwiftGTD-macOS" | head -1)

    if [ -n "$APP_PATH" ]; then
        echo "📦 Found app at: $APP_PATH"

        # Get or boot a simulator
        SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 15" | grep "(Booted)" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)

        if [ -z "$SIMULATOR_ID" ]; then
            echo "📱 Booting iPhone 15 simulator..."
            SIMULATOR_ID=$(xcrun simctl list devices | grep "iPhone 15" | head -1 | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')
            open -a Simulator
            xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
            sleep 3
        fi

        echo "📲 Installing app..."
        xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

        BUNDLE_ID="com.swiftgtd.app"
        echo "🚀 Launching app..."
        xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

        echo "✨ iOS app launched successfully!"
    else
        echo "❌ Could not find built iOS app"
    fi
else
    echo "❌ Build failed"
    exit 1
fi