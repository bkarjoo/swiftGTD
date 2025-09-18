#!/bin/bash

echo "=========================================="
echo "Monitoring SwiftGTD Logs for Task Toggle"
echo "=========================================="
echo ""
echo "This script will monitor the console output of the running SwiftGTD app."
echo "Please click on a task checkbox in the simulator to test the toggle functionality."
echo ""
echo "Watching for task toggle related logs..."
echo "=========================================="
echo ""

# Get the PID of the running SwiftGTD app
PID=$(xcrun simctl spawn 85942F58-E9E5-444B-AF75-E2177C45343A launchctl list | grep com.behrooz.SwiftGTD1 | awk '{print $1}')

if [ -z "$PID" ]; then
    echo "SwiftGTD app is not running. Please launch it first."
    exit 1
fi

echo "Found SwiftGTD app with PID: $PID"
echo ""
echo "Monitoring logs... (Press Ctrl+C to stop)"
echo "=========================================="
echo ""

# Stream logs from the specific process and filter for our logging statements
xcrun simctl spawn 85942F58-E9E5-444B-AF75-E2177C45343A log stream --predicate "processID == $PID" | grep -E "TreeNodeView|TreeViewModel|DataManager|APIClient|toggleTask|Task checkbox"