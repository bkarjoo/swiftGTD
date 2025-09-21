#!/bin/bash

echo "SwiftGTD Rebuild Script"
echo "======================="

# Get bundle ID from parameter or use default
APP_BUNDLE_ID="${1:-com.behrooz.SwiftGTD1}"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [bundle_id] [simulator_id]"
    echo "Default bundle ID: com.behrooz.SwiftGTD1"
    exit 0
fi

echo "Using bundle ID: $APP_BUNDLE_ID"

# Get simulator ID from parameter or auto-detect
if [ ! -z "$2" ]; then
    SIMULATOR_ID="$2"
    echo "Using specified simulator: $SIMULATOR_ID"
else
    # Get list of booted simulators
    BOOTED_SIMS=$(xcrun simctl list devices | grep "(Booted)" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')
    SIM_COUNT=$(echo "$BOOTED_SIMS" | grep -c .)
    
    if [ $SIM_COUNT -eq 0 ]; then
        echo "No booted simulator found. Please boot a simulator first."
        echo ""
        echo "To boot a simulator, run:"
        echo "  xcrun simctl boot <device_id>"
        echo ""
        echo "Available simulators:"
        xcrun simctl list devices | grep -E "iPhone|iPad" | grep -v "(Unavailable)" | head -10
        exit 1
    elif [ $SIM_COUNT -eq 1 ]; then
        SIMULATOR_ID="$BOOTED_SIMS"
        echo "Using booted simulator: $SIMULATOR_ID"
    else
        echo "Multiple booted simulators found. Please select one:"
        echo ""
        i=1
        while IFS= read -r sim_id; do
            echo "  $i) $sim_id"
            i=$((i+1))
        done <<< "$BOOTED_SIMS"
        echo ""
        echo "Run: $0 $APP_BUNDLE_ID <simulator_id>"
        exit 1
    fi
fi

# Clear all log directories for a fresh start
if [ "$3" != "--keep-logs" ]; then
    echo "Clearing all log directories..."
    rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Application\ Support/Logs/ 2>/dev/null
    echo "✅ Log directories cleared"
else
    echo "Keeping existing logs (--keep-logs flag set)"
fi

# Clean build
echo "Cleaning build..."
xcodebuild clean -project SwiftGTD.xcodeproj -scheme SwiftGTD -destination "platform=iOS Simulator,id=$SIMULATOR_ID" > /dev/null 2>&1

# Build the app
echo "Building SwiftGTD..."
xcodebuild build -project SwiftGTD.xcodeproj -scheme SwiftGTD -destination "platform=iOS Simulator,id=$SIMULATOR_ID" 2>&1 | while read line; do
    if echo "$line" | grep -E "(Building|Compiling|Linking|error:|warning:|BUILD)" > /dev/null; then
        echo "$line"
    fi
done

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful"

# Install and run
./install_and_run.sh "$APP_BUNDLE_ID" "$SIMULATOR_ID"