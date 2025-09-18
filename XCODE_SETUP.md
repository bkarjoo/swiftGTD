# Xcode Setup Instructions

After checkpoint 7, you need to manually configure Xcode to use the Swift Package modules:

## Steps to Configure Xcode

1. **Open the project in Xcode**
   ```
   open SwiftGTD.xcodeproj
   ```

2. **Add the local Swift Package**
   - In Xcode, go to File → Add Package Dependencies
   - Click "Add Local..."
   - Navigate to and select the `Packages` folder
   - Click "Add Package"

3. **Add package products to target**
   - Select the SwiftGTD project in the navigator
   - Select the SwiftGTD target
   - Go to the "General" tab
   - In "Frameworks, Libraries, and Embedded Content" section, click "+"
   - Add these package products:
     - Core
     - Models
     - Networking
     - Services
     - Features

4. **Clean and build**
   - Press Cmd+Shift+K to clean
   - Press Cmd+B to build

## Troubleshooting

If you see "No such module" errors:
1. Make sure all 5 package products are added to the target
2. Clean build folder: Cmd+Shift+Option+K
3. Close and reopen Xcode
4. Build again

If the Packages folder isn't recognized:
1. Make sure you're adding the `Packages` folder, not individual modules
2. The Package.swift file should be at `Packages/Package.swift`