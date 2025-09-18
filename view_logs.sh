#!/bin/bash

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
        echo "Available simulators:"
        xcrun simctl list devices | grep -E "iPhone|iPad" | grep -v "(Shutdown)" | head -10
        exit 1
    elif [ $SIM_COUNT -eq 1 ]; then
        SIMULATOR_ID="$BOOTED_SIMS"
        echo "Using booted simulator: $SIMULATOR_ID"
    else
        echo "Multiple booted simulators found. Please select one:"
        echo ""
        i=1
        while IFS= read -r sim_id; do
            DEVICE_NAME=$(xcrun simctl list devices | grep "$sim_id" | sed 's/.*(\(.*\)).*/\1/' | head -1)
            echo "  $i) $sim_id"
            i=$((i+1))
        done <<< "$BOOTED_SIMS"
        echo ""
        echo "Run: $0 $APP_BUNDLE_ID <simulator_id>"
        exit 1
    fi
fi

# Find the app's Application Support directory (new location)
APP_DIR=$(find ~/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Data/Application -name "$APP_BUNDLE_ID" -type d 2>/dev/null | head -1)

if [ -z "$APP_DIR" ]; then
    echo "App not found. Please run the app first."
    exit 1
fi

# Get the container ID from the path
CONTAINER_ID=$(echo "$APP_DIR" | sed 's/.*Application\///' | sed 's/\/.*//')

# Try new location (Application Support/Logs)
LOG_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Data/Application/$CONTAINER_ID/Library/Application Support/Logs"
LOG_FILE="$LOG_DIR/swiftgtd.log"

# Fall back to old location (Documents) if new location doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    LOG_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Data/Application/$CONTAINER_ID/Documents"
    LOG_FILE="$LOG_DIR/swiftgtd.log"
fi

echo "Log directory: $LOG_DIR"
echo "=========================================="

if [ -f "$LOG_FILE" ]; then
    echo "SwiftGTD Log:"
    echo ""
    # Check for compressed archives
    if ls "$LOG_DIR"/swiftgtd.log.*.gz 1> /dev/null 2>&1; then
        echo "Archived logs available:"
        ls -lh "$LOG_DIR"/swiftgtd.log.*.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
        echo ""
    fi
    tail -f "$LOG_FILE"
else
    echo "No log file found yet. Run the app and perform some actions."
fi