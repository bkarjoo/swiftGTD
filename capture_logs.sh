#!/bin/bash

# Kill any existing app instances
xcrun simctl terminate 85942F58-E9E5-444B-AF75-E2177C45343A com.behrooz.SwiftGTD1 2>/dev/null

# Clear console
clear

echo "=========================================="
echo "Starting SwiftGTD App with Console Logging"
echo "=========================================="
echo ""
echo "Instructions:"
echo "1. Wait for app to load"
echo "2. Click on a task checkbox to toggle its completion status"
echo "3. Watch the logs below to see the execution flow"
echo "4. Press Ctrl+C to stop"
echo ""
echo "Launching app..."
echo "=========================================="
echo ""

# Launch the app and capture console output
xcrun simctl launch --console-pty 85942F58-E9E5-444B-AF75-E2177C45343A com.behrooz.SwiftGTD1