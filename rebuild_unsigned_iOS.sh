#!/bin/bash

# Rebuild iOS app without code signing

echo "📱 Building iOS app (unsigned)..."
xcodebuild -scheme SwiftGTD \
    build \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | grep -E "^(Building|Compiling|Linking|Processing|Copying|Touch|Create|Write|Generate|warning:|error:|BUILD)"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded"

    # Open the Simulator
    echo "🚀 Opening iOS Simulator..."
    open -a Simulator

    # Wait for simulator to start
    sleep 3

    # Install and launch the app
    echo "📲 Installing app on simulator..."
    xcrun simctl install booted /Users/behroozkarjoo/Library/Developer/Xcode/DerivedData/SwiftGTD-*/Build/Products/Debug-iphonesimulator/SwiftGTD.app

    echo "🚀 Launching app..."
    xcrun simctl launch booted com.swiftgtd.SwiftGTD
else
    echo "❌ Build failed"
    exit 1
fi