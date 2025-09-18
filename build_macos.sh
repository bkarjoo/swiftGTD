#!/bin/bash

echo "Building SwiftGTD for macOS..."
echo "=============================="

# Build the packages first
cd Packages
swift build -Xswiftc -target -Xswiftc x86_64-apple-macosx13.0

if [ $? -ne 0 ]; then
    echo "❌ Package build failed"
    exit 1
fi

echo "✅ Packages built successfully"

# For now, just compile the macOS app file to verify it works
cd ../SwiftGTD-macOS
swiftc -parse SwiftGTDApp_macOS.swift \
    -I ../Packages/.build/x86_64-apple-macosx/debug \
    -L ../Packages/.build/x86_64-apple-macosx/debug \
    -lCore -lModels -lServices -lFeatures -lNetworking \
    -sdk $(xcrun --sdk macosx --show-sdk-path) \
    -target x86_64-apple-macosx13.0

if [ $? -eq 0 ]; then
    echo "✅ macOS app structure validated"
else
    echo "❌ macOS app compilation check failed"
fi