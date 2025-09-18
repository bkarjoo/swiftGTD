# Test Credentials

**⚠️ FOR TESTING ONLY - DO NOT USE IN PRODUCTION**

## Setting Up Test Credentials

For testing, you should:

1. **Create your own test account** on your local backend
2. **Never commit real credentials** to version control
3. **Use environment variables** for test credentials

## Example Structure (DO NOT USE THESE VALUES)
```bash
# Set these in your local environment or test configuration
export TEST_EMAIL="your-test@example.com"
export TEST_PASSWORD="your-test-password"
export TEST_API_URL="http://localhost:8003"
```

## Usage in Tests
```swift
// Load from environment or configuration
let testEmail = ProcessInfo.processInfo.environment["TEST_EMAIL"] ?? "test@example.com"
let testPassword = ProcessInfo.processInfo.environment["TEST_PASSWORD"] ?? "changeme"
```

## Security Notes
- Never commit real user credentials
- Use unique test accounts per developer
- Rotate test credentials regularly
- Do not share test credentials in documentation
- Use environment variables or secure configuration files