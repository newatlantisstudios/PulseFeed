#!/bin/bash

# Quick build script - fastest build with minimal output
#
# Usage:
#   ./quick_build.sh        # Ultra-quiet build, shows only errors
#   ./quick_build.sh watch  # Watch mode - rebuilds on file changes

set -e

# Configuration
SCHEME="PulseFeed"
CONFIG="Debug"
WATCH_MODE=false

# Parse arguments
if [ "$1" = "watch" ]; then
    WATCH_MODE=true
fi

# Function to perform quick build
quick_build() {
    # Show minimal info
    echo -n "🚀 Building... "
    
    # Build with maximum quiet settings
    if xcodebuild build \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -derivedDataPath ./DerivedData \
        -quiet \
        -hideShellScriptEnvironment \
        -parallelizeTargets \
        2>&1 | grep -E "(error:|FAILED)" || true; then
        echo "✅"
    else
        echo "❌"
        exit 1
    fi
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
    echo "👀 Watch mode enabled. Press Ctrl+C to stop."
    echo ""
    
    # Initial build
    quick_build
    
    # Watch for changes
    while true; do
        # Use fswatch if available, otherwise fall back to simple loop
        if command -v fswatch &> /dev/null; then
            fswatch -o PulseFeed --exclude="DerivedData" -e ".*\.tmp$" | while read; do
                echo ""
                quick_build
            done
        else
            # Simple polling fallback
            sleep 2
            if find PulseFeed -name "*.swift" -newer .last_build 2>/dev/null | grep -q .; then
                touch .last_build
                echo ""
                quick_build
            fi
        fi
    done
else
    # Single quick build
    quick_build
    echo "💨 Done in $(date -u '+%M:%S')"
fi