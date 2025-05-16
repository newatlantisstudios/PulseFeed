#!/bin/bash

# Test script with xcbeautify and quiet mode
#
# Usage:
#   ./test.sh               # Run all tests with quiet output
#   ./test.sh verbose       # Verbose test output
#   ./test.sh MyTestClass   # Run specific test class
#   ./test.sh coverage      # Run tests with coverage report

set -e

# Default configuration
SCHEME="PulseFeed"
QUIET="-quiet"
BEAUTIFY=true
SPECIFIC_TEST=""
COVERAGE=false

# Parse arguments
case "${1:-default}" in
    "verbose")
        QUIET=""
        BEAUTIFY=false
        ;;
    "coverage")
        COVERAGE=true
        ;;
    "default")
        ;;
    *)
        # Assume it's a specific test class/method
        SPECIFIC_TEST="-only-testing:PulseFeed/$1"
        ;;
esac

echo "🧪 Running tests for PulseFeed..."
echo "📍 Project: $(pwd)"
echo ""

# Base test command
TEST_CMD="xcodebuild test \
    -scheme $SCHEME \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -derivedDataPath ./DerivedData \
    $QUIET"

# Add coverage flag if requested
if [ "$COVERAGE" = true ]; then
    TEST_CMD="$TEST_CMD -enableCodeCoverage YES"
fi

# Add specific test if provided
if [ -n "$SPECIFIC_TEST" ]; then
    TEST_CMD="$TEST_CMD $SPECIFIC_TEST"
    echo "🎯 Running specific test: $1"
fi

# Run tests
if [ "$BEAUTIFY" = true ]; then
    # Test with xcbeautify
    TEST_OUTPUT=$(mktemp)
    if $TEST_CMD 2>&1 | tee "$TEST_OUTPUT" | xcbeautify; then
        echo "✅ Tests passed!"
        
        # Extract test summary
        TESTS_RUN=$(grep -E "Test Suite .* passed" "$TEST_OUTPUT" | wc -l || echo "0")
        TESTS_FAILED=$(grep -E "Test Suite .* failed" "$TEST_OUTPUT" | wc -l || echo "0")
        
        echo ""
        echo "📊 Test Summary:"
        echo "   Total: $((TESTS_RUN + TESTS_FAILED))"
        echo "   Passed: $TESTS_RUN"
        echo "   Failed: $TESTS_FAILED"
        
        # Show coverage if enabled
        if [ "$COVERAGE" = true ]; then
            echo ""
            echo "📈 Generating coverage report..."
            
            # Generate coverage report
            xcrun xccov view --report ./DerivedData/Logs/Test/*.xcresult | head -20
            
            echo ""
            echo "💡 Full coverage report available at:"
            echo "   ./DerivedData/Logs/Test/*.xcresult"
        fi
    else
        echo "❌ Tests failed!"
        
        # Show failing tests
        echo ""
        echo "Failed tests:"
        grep -E "error:|failed:|Test Case .* failed" "$TEST_OUTPUT" | sort -u | head -10
        
        exit 1
    fi
    rm -f "$TEST_OUTPUT"
else
    # Verbose test without beautify
    if $TEST_CMD; then
        echo "✅ Tests passed!"
    else
        echo "❌ Tests failed!"
        exit 1
    fi
fi

# Show test time
echo ""
echo "⏱️  Tests completed in $(date -u '+%M:%S')"