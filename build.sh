#!/bin/bash

echo "=========================================="
echo "SwiftGTD Build Script"
echo "=========================================="

# Find and clear log files from simulator
echo "Clearing old log files..."
find ~/Library/Developer/CoreSimulator/Devices -name "swiftgtd.log" 2>/dev/null | while read logfile; do
    echo "  Removing: $(basename $logfile)"
    rm -f "$logfile"
done

# Build the app
echo ""
echo "Building SwiftGTD..."
xcodebuild -scheme SwiftGTD -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build succeeded!"
    echo ""
    echo "To install and run:"
    echo "  ./install_and_run.sh"
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi