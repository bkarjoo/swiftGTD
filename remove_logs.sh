#!/bin/bash

echo "Removing all SwiftGTD logs..."
find ~/Library/Developer/CoreSimulator/Devices -name "swiftgtd.log*" -type f -delete 2>/dev/null
echo "✅ Logs removed"