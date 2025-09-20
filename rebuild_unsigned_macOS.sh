#!/bin/bash

# Rebuild macOS app without code signing

echo "🔨 Building macOS app (unsigned)..."

# Build with local derivedDataPath and no entitlements
xcodebuild -scheme SwiftGTD-macOS \
    -configuration Debug \
    -derivedDataPath build \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS="" \
    PRODUCT_BUNDLE_IDENTIFIER="com.local.SwiftGTD-macOS" \
    build 2>&1 | while IFS= read -r line; do
        # Show progress but filter out noise
        if echo "$line" | grep -E "(Building|Compiling|Linking|Processing|Copying|▸|warning:|error:|BUILD|FAILED|Succeeded)" > /dev/null; then
            echo "$line"
        fi
    done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Build succeeded"

    # Find the built app
    APP_PATH=$(find build -name "SwiftGTD-macOS.app" -type d | head -1)

    if [ -z "$APP_PATH" ]; then
        echo "❌ Could not find built app"
        exit 1
    fi

    echo "📦 Found app at: $APP_PATH"

    # Kill existing app if running
    killall SwiftGTD-macOS 2>/dev/null && echo "🛑 Killed existing app"

    # Wait a moment
    sleep 1

    # Open the newly built app
    echo "🚀 Launching app..."
    open "$APP_PATH"
else
    echo "❌ Build failed"
    exit 1
fi