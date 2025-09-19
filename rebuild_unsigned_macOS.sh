#!/bin/bash

# Rebuild macOS app without code signing

echo "🔨 Building macOS app (unsigned)..."
xcodebuild -scheme SwiftGTD-macOS \
    build \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | grep -E "^(Building|Compiling|Linking|Processing|Copying|Touch|Create|Write|Generate|warning:|error:|BUILD)"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded"

    # Kill existing app if running
    killall SwiftGTD-macOS 2>/dev/null && echo "🛑 Killed existing app"

    # Wait a moment
    sleep 1

    # Open the newly built app
    echo "🚀 Launching app..."
    open /Users/behroozkarjoo/Library/Developer/Xcode/DerivedData/SwiftGTD-*/Build/Products/Debug/SwiftGTD-macOS.app
else
    echo "❌ Build failed"
    exit 1
fi