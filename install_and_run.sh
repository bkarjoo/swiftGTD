#!/bin/bash

# Get bundle ID from parameter or use default
APP_ID="${1:-com.behrooz.SwiftGTD1}"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [bundle_id] [simulator_id]"
    echo "Default bundle ID: com.behrooz.SwiftGTD1"
    exit 0
fi

echo "Using bundle ID: $APP_ID"

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
        echo "Run: $0 $APP_ID <simulator_id>"
        exit 1
    fi
fi

# Find the most recent build in DerivedData (excluding Index.noindex)
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "SwiftGTD.app" -path "*/Debug-iphonesimulator/*" -type d 2>/dev/null | grep -v "Index.noindex" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "SwiftGTD.app not found. Please build the app first."
    exit 1
fi

echo "Using app at: $APP_PATH"

echo "Installing and running SwiftGTD..."

# Terminate if running
xcrun simctl terminate $SIMULATOR_ID $APP_ID 2>/dev/null

# Install
xcrun simctl install $SIMULATOR_ID "$APP_PATH"

# Launch
xcrun simctl launch $SIMULATOR_ID $APP_ID

echo "✅ App launched!"
echo ""
echo "To view logs:"
echo "  ./view_logs.sh $APP_ID $SIMULATOR_ID"