#!/bin/bash

# Build script with xcbeautify and quiet mode
#
# Usage:
#   ./build.sh              # Default debug build with quiet output
#   ./build.sh verbose      # Verbose build without beautify
#   ./build.sh release      # Release build with quiet output
#   ./build.sh clean        # Clean build folder
#   ./build.sh check        # Build and check for errors/warnings

set -e

# Default configuration
CONFIG="Debug"
SCHEME="PulseFeed"
QUIET="-quiet"
BEAUTIFY=true
CHECK_ERRORS=false

# Parse arguments
case "${1:-default}" in
    "verbose")
        QUIET=""
        BEAUTIFY=false
        ;;
    "release")
        CONFIG="Release"
        ;;
    "clean")
        echo "🧹 Cleaning build folder..."
        xcodebuild clean -scheme "$SCHEME" -derivedDataPath ./DerivedData | xcbeautify
        rm -rf ./DerivedData
        echo "✅ Clean complete!"
        exit 0
        ;;
    "check")
        CHECK_ERRORS=true
        ;;
    "default")
        ;;
    *)
        echo "❌ Unknown argument: $1"
        echo "Usage: ./build.sh [verbose|release|clean|check]"
        exit 1
        ;;
esac

echo "🔨 Building PulseFeed ($CONFIG)..."
echo "📍 Project: $(pwd)"
echo ""

# Build command
BUILD_CMD="xcodebuild build \
    -scheme $SCHEME \
    -configuration $CONFIG \
    -derivedDataPath ./DerivedData \
    $QUIET"

if [ "$BEAUTIFY" = true ]; then
    # Build with xcbeautify
    if [ "$CHECK_ERRORS" = true ]; then
        # Capture both stdout and stderr for error checking
        BUILD_OUTPUT=$(mktemp)
        if $BUILD_CMD 2>&1 | tee "$BUILD_OUTPUT" | xcbeautify; then
            echo "✅ Build succeeded!"
            
            # Check for warnings
            WARNING_COUNT=$(grep -c "warning:" "$BUILD_OUTPUT" || true)
            ERROR_COUNT=$(grep -c "error:" "$BUILD_OUTPUT" || true)
            
            if [ "$WARNING_COUNT" -gt 0 ]; then
                echo "⚠️  Found $WARNING_COUNT warnings"
                echo ""
                echo "Warnings:"
                grep "warning:" "$BUILD_OUTPUT" | sort -u | head -10
                echo ""
            fi
            
            if [ "$ERROR_COUNT" -gt 0 ]; then
                echo "❌ Found $ERROR_COUNT errors"
                echo ""
                echo "Errors:"
                grep "error:" "$BUILD_OUTPUT" | sort -u
                echo ""
                exit 1
            fi
            
            if [ "$WARNING_COUNT" -eq 0 ] && [ "$ERROR_COUNT" -eq 0 ]; then
                echo "🎉 No warnings or errors found!"
            fi
        else
            echo "❌ Build failed!"
            exit 1
        fi
        rm -f "$BUILD_OUTPUT"
    else
        # Regular build with beautify
        if $BUILD_CMD | xcbeautify; then
            echo "✅ Build succeeded!"
        else
            echo "❌ Build failed!"
            exit 1
        fi
    fi
else
    # Verbose build without beautify
    if $BUILD_CMD; then
        echo "✅ Build succeeded!"
    else
        echo "❌ Build failed!"
        exit 1
    fi
fi

# Show build time
echo ""
echo "⏱️  Build completed in $(date -u '+%M:%S')"