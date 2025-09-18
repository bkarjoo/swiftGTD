#!/bin/bash

echo "Swift files that need to be added to Xcode project:"
echo "===================================================="
echo ""

cd /Users/behroozkarjoo/dev/swiftgtd/SwiftGTD

echo "Models:"
ls -1 Models/*.swift 2>/dev/null | sed 's/^/  - /'

echo ""
echo "Views:"
ls -1 Views/*.swift 2>/dev/null | sed 's/^/  - /'

echo ""
echo "ViewModels:"
ls -1 ViewModels/*.swift 2>/dev/null | sed 's/^/  - /'

echo ""
echo "Services:"
ls -1 Services/*.swift 2>/dev/null | sed 's/^/  - /'

echo ""
echo "Utils:"
ls -1 Utils/*.swift 2>/dev/null | sed 's/^/  - /'

echo ""
echo "Root level Swift files:"
ls -1 *.swift 2>/dev/null | sed 's/^/  - /'

echo ""
echo "===================================================="
echo "To add these files to Xcode:"
echo "1. Open SwiftGTD.xcodeproj in Xcode"
echo "2. Right-click on the SwiftGTD folder in the navigator"
echo "3. Select 'Add Files to SwiftGTD...'"
echo "4. Navigate to each folder and select all .swift files"
echo "5. Make sure 'Create groups' is selected"
echo "6. Make sure 'Add to targets: SwiftGTD' is checked"