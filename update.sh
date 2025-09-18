#!/bin/bash

echo "Updating SwiftGTD..."
echo "==================="

# Pull latest changes
echo "Pulling latest changes..."
git pull

if [ $? -ne 0 ]; then
    echo "❌ Git pull failed. Please resolve conflicts."
    exit 1
fi

# Clean and rebuild
echo "Rebuilding app..."
./rebuild_macOS.sh

echo "✅ Update complete!"