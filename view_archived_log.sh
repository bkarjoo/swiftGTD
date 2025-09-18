#!/bin/bash

# Get bundle ID from parameter or use default
APP_BUNDLE_ID="${1:-com.behrooz.SwiftGTD1}"
ARCHIVE_NUM="${2:-1}"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [bundle_id] [archive_number] [simulator_id]"
    echo "Default bundle ID: com.behrooz.SwiftGTD1"
    echo "Archive number: 1-5 (1 is most recent)"
    exit 0
fi

echo "Using bundle ID: $APP_BUNDLE_ID"
echo "Archive number: $ARCHIVE_NUM"

# Get simulator ID from parameter or auto-detect
if [ ! -z "$3" ]; then
    SIMULATOR_ID="$3"
    echo "Using specified simulator: $SIMULATOR_ID"
else
    # Get list of booted simulators
    BOOTED_SIMS=$(xcrun simctl list devices | grep "(Booted)" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}')
    SIM_COUNT=$(echo "$BOOTED_SIMS" | grep -c .)
    
    if [ $SIM_COUNT -eq 0 ]; then
        echo "No booted simulator found. Using first available simulator."
        SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone|iPad" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)
    elif [ $SIM_COUNT -eq 1 ]; then
        SIMULATOR_ID="$BOOTED_SIMS"
        echo "Using booted simulator: $SIMULATOR_ID"
    else
        echo "Multiple booted simulators found. Using first one."
        SIMULATOR_ID=$(echo "$BOOTED_SIMS" | head -1)
    fi
fi

# Find the app's Application Support directory
APP_DIR=$(find ~/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Data/Application -name "$APP_BUNDLE_ID" -type d 2>/dev/null | head -1)

if [ -z "$APP_DIR" ]; then
    echo "App not found."
    exit 1
fi

# Get the container ID from the path
CONTAINER_ID=$(echo "$APP_DIR" | sed 's/.*Application\///' | sed 's/\/.*//')

# Check new location first
LOG_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Data/Application/$CONTAINER_ID/Library/Application Support/Logs"
ARCHIVE_FILE="$LOG_DIR/swiftgtd.log.$ARCHIVE_NUM.gz"

# Fall back to old location if needed
if [ ! -f "$ARCHIVE_FILE" ]; then
    LOG_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$SIMULATOR_ID/data/Containers/Data/Application/$CONTAINER_ID/Documents"
    ARCHIVE_FILE="$LOG_DIR/swiftgtd.log.$ARCHIVE_NUM.gz"
fi

if [ -f "$ARCHIVE_FILE" ]; then
    echo "Viewing archive: $ARCHIVE_FILE"
    echo "=========================================="
    gunzip -c "$ARCHIVE_FILE" | less
else
    echo "Archive not found: swiftgtd.log.$ARCHIVE_NUM.gz"
    echo ""
    echo "Available archives in $LOG_DIR:"
    ls -lh "$LOG_DIR"/swiftgtd.log.*.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
fi