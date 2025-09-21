#!/bin/bash

echo "📱 Building iOS app..."

# Clean
echo "🧹 Cleaning..."
rm -rf build

# Get the booted simulator
SIMULATOR_ID=$(xcrun simctl list devices | grep "(Booted)" | head -1 | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')

if [ -z "$SIMULATOR_ID" ]; then
    echo "❌ No booted simulator found. Booting iPhone 16 Pro..."
    SIMULATOR_ID="85942F58-E9E5-444B-AF75-E2177C45343A"
    open -a Simulator
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    sleep 3
else
    echo "✅ Using booted simulator: $SIMULATOR_ID"
fi

# Build
echo "🔨 Building for iOS..."
xcodebuild \
    -project SwiftGTD.xcodeproj \
    -scheme SwiftGTD \
    -destination "id=$SIMULATOR_ID" \
    -derivedDataPath build \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -E "(Building|Compiling|Linking|error:|warning:|BUILD|FAILED|Succeeded)" > /dev/null; then
            echo "$line"
        fi
    done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded!"

    # Find the app
    APP_PATH=$(find build -name "SwiftGTD.app" -path "*/Debug-iphonesimulator/*" -type d | head -1)

    if [ -n "$APP_PATH" ]; then
        echo "📦 Found app at: $APP_PATH"

        echo "📲 Installing app..."
        xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

        echo "🚀 Launching app..."
        xcrun simctl launch "$SIMULATOR_ID" "com.swiftgtd.app"

        echo "✨ iOS app launched!"
    else
        echo "❌ Could not find iOS app"
    fi
else
    echo "❌ Build failed"

    # Try a different approach - build without scheme
    echo "🔧 Trying alternative build approach..."
    xcodebuild \
        -project SwiftGTD.xcodeproj \
        -target SwiftGTD \
        -configuration Debug \
        -sdk iphonesimulator \
        -derivedDataPath build \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        ONLY_ACTIVE_ARCH=NO \
        build
fi