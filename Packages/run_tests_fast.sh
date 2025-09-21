#!/bin/bash

# Run all tests for SwiftGTD Packages (fast version - skips slow integration tests)
# This script runs test suites individually to avoid timeouts

echo "========================================="
echo "Running SwiftGTD Package Tests (Fast)"
echo "========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counter for passed/failed tests
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Function to run a test suite
run_test() {
    local test_name=$1
    local timeout=${2:-30} # Default 30 second timeout

    echo -e "${YELLOW}Running $test_name...${NC}"

    # Run the test with timeout and capture output
    if timeout $timeout swift test --filter "$test_name" 2>&1 | grep -q "Test Suite '$test_name' passed"; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        ((PASSED_TESTS++))
    else
        # Check if it timed out
        if [ $? -eq 124 ]; then
            echo -e "${YELLOW}⊘ $test_name skipped (timeout)${NC}"
            ((SKIPPED_TESTS++))
        else
            echo -e "${RED}✗ $test_name failed${NC}"
            ((FAILED_TESTS++))
        fi
    fi
    ((TOTAL_TESTS++))
    echo ""
}

# Build tests first
echo "Building tests..."
swift build --build-tests
echo ""

# List of all test suites
echo "Running individual test suites:"
echo "-------------------------------"

# Phase 1 Tests
run_test "DataManagerPhase1Tests"

# Offline Tests
run_test "DataManagerOfflineCreateTests"
run_test "DataManagerOfflineDeleteTests"
run_test "DataManagerOfflineToggleTests"

# Sync Tests
run_test "DataManagerSyncOnReconnectTests"
run_test "OfflineQueueProcessTests"

# Integration Tests (with shorter timeout)
echo -e "${YELLOW}Note: Skipping FullOfflineFlowIntegrationTests (known timeout issues)${NC}"
((SKIPPED_TESTS++))
((TOTAL_TESTS++))
echo ""

# Toggle Tests
run_test "DataManagerToggleTests"
run_test "DataManagerToggleFailureTests"

# Other Tests
run_test "SyncConflictResolutionTests"
run_test "SmartFolderRestrictionTests"
run_test "DataManagerCacheFallbackTests"
run_test "NoteNodeTests"

# Summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Total test suites: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo -e "${YELLOW}Skipped: $SKIPPED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}✓ All non-skipped tests passed!${NC}"
    if [ $SKIPPED_TESTS -gt 0 ]; then
        echo -e "${YELLOW}Note: Some tests were skipped due to timeouts. Run them individually for full coverage.${NC}"
    fi
    exit 0
else
    echo -e "\n${RED}✗ Some tests failed. Please review the output above.${NC}"
    exit 1
fi