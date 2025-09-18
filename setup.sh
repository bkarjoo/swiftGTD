#!/bin/bash

echo "SwiftGTD Setup Script"
echo "===================="
echo

# Check if Xcode is installed
if [ ! -d "/Applications/Xcode.app" ]; then
    echo "❌ Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi

# Set Xcode as active developer directory
echo "Setting Xcode as active developer directory..."
echo "You will be prompted for your password:"
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

if [ $? -eq 0 ]; then
    echo "✅ Xcode developer directory set successfully"
else
    echo "❌ Failed to set Xcode developer directory"
    exit 1
fi

# Check if Config.xcconfig exists
if [ ! -f "Config.xcconfig" ]; then
    echo "Creating Config.xcconfig from example..."
    cp Config.xcconfig.example Config.xcconfig
    echo "✅ Config.xcconfig created"
    echo "⚠️  Please edit Config.xcconfig to set your API URL"
else
    echo "✅ Config.xcconfig already exists"
fi

echo
echo "Setup complete!"
echo
echo "Next steps:"
echo "1. Make sure your API server is running at http://100.68.27.105:8003"
echo "2. Run ./rebuild_iOS.sh 2>&1 | tee ios_build.log    # Build iOS and save output"
echo "3. Or run ./rebuild_macOS.sh 2>&1 | tee macos_build.log  # Build macOS and save output"
echo
echo "The build output will be saved to ios_build.log or macos_build.log for examination"