#!/bin/bash

# Generate timestamp for unique filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="test_results_${TIMESTAMP}.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Running SwiftGTD Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "📝 Test output will be saved to: ${GREEN}${LOG_FILE}${NC}"
echo -e "🕐 Started at: $(date)"
echo ""

# Write header to log file
echo "SwiftGTD Test Run - $(date)" > "$LOG_FILE"
echo "════════════════════════════════════════════════════════" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Change to Packages directory and run tests
cd Packages 2>/dev/null || cd /Users/behroozkarjoo/dev/swiftgtd/Packages

echo -e "${BLUE}Running tests...${NC}"
echo ""

# Run tests and capture output
if swift test >> "../${LOG_FILE}" 2>&1; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo "" >> "../${LOG_FILE}"
    echo "All tests passed at $(date)" >> "../${LOG_FILE}"
    EXIT_CODE=0
else
    echo -e "${RED}❌ Some tests failed!${NC}"
    echo "" >> "../${LOG_FILE}"
    echo "Tests failed at $(date)" >> "../${LOG_FILE}"
    EXIT_CODE=1
fi

# Back to original directory
cd - > /dev/null 2>&1

echo ""
echo -e "🏁 Finished at: $(date)"
echo -e "📄 Full results saved in: ${GREEN}${LOG_FILE}${NC}"
echo ""

# Show summary
echo -e "${BLUE}Test Summary:${NC}"
echo "────────────────────────────────────────────────────────"

# Extract and display test counts
if command -v grep &> /dev/null; then
    PASSED=$(grep -c "Test Case.*passed" "$LOG_FILE" 2>/dev/null || echo "0")
    FAILED=$(grep -c "Test Case.*failed" "$LOG_FILE" 2>/dev/null || echo "0")

    echo -e "✅ Passed: ${GREEN}${PASSED}${NC}"
    if [ "$FAILED" -gt 0 ]; then
        echo -e "❌ Failed: ${RED}${FAILED}${NC}"
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        grep "Test Case.*failed" "$LOG_FILE" 2>/dev/null | head -10 || true

        if [ "$FAILED" -gt 10 ]; then
            echo "  ... and $((FAILED - 10)) more"
        fi
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

# Return appropriate exit code
exit $EXIT_CODE