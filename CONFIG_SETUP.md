# Configuration Setup

## Overview

SwiftGTD uses an `.xcconfig` file to manage environment-specific settings like API URLs. This keeps sensitive information out of the codebase.

## Initial Setup

1. **Copy the example configuration file:**
   ```bash
   cp Config.xcconfig.example Config.xcconfig
   ```

2. **Edit `Config.xcconfig` with your API URL:**
   ```
   // For local development
   API_BASE_URL = http:/$()/localhost:8003

   // For Tailscale network
   API_BASE_URL = http:/$()/your-tailscale-ip:8003

   // For production
   API_BASE_URL = https:/$()/api.yourapp.com
   ```

   **Note:** The `$()` is required in xcconfig files to escape the slashes in URLs.

3. **Configure Xcode to use the config file:**
   - Open the project in Xcode
   - Select the project file in the navigator
   - Select the project (not a target) in the editor
   - In the Info tab, under Configurations:
     - For Debug configuration, set "Based on Configuration File" to `Config.xcconfig`
     - For Release configuration, set "Based on Configuration File" to `Config.xcconfig`

## Important Notes

- **Never commit `Config.xcconfig` to version control** - it contains your personal API endpoints
- The `.gitignore` file already excludes `Config.xcconfig`
- Always update `Config.xcconfig.example` when adding new configuration keys
- The app will default to `http://localhost:8003` if no configuration is found

## Troubleshooting

If the app can't connect to your API:

1. Check that `Config.xcconfig` exists and has the correct URL
2. Verify the xcconfig file is properly linked in Xcode project settings
3. Clean and rebuild the project (Cmd+Shift+K, then Cmd+B)
4. Check that your API server is running and accessible

## For Different Environments

You can create multiple config files for different environments:

- `Config.Debug.xcconfig` - Development settings
- `Config.Release.xcconfig` - Production settings
- `Config.Staging.xcconfig` - Staging settings

Then assign different config files to different build configurations in Xcode.