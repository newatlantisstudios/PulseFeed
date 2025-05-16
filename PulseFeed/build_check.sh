#!/bin/bash

# Build check script - performs various build checks and analyses
#
# Usage:
#   ./build_check.sh            # Run all checks
#   ./build_check.sh analyze    # Run static analysis only
#   ./build_check.sh swift      # Check Swift version and settings
#   ./build_check.sh deps       # Check dependencies

set -e

# Default configuration
SCHEME="PulseFeed"
CHECK_TYPE="${1:-all}"

echo "🔍 PulseFeed Build Check"
echo "📍 Project: $(pwd)"
echo ""

# Function to check Swift version
check_swift_version() {
    echo "🔧 Swift Environment:"
    echo "   Swift version: $(swift --version | head -1)"
    echo "   Xcode version: $(xcodebuild -version | head -1)"
    echo ""
}

# Function to analyze build settings
check_build_settings() {
    echo "⚙️  Build Settings Check:"
    xcodebuild -scheme "$SCHEME" -showBuildSettings | grep -E "(SWIFT_VERSION|DEPLOYMENT_TARGET|VALID_ARCHS)" | sort -u
    echo ""
}

# Function to check dependencies
check_dependencies() {
    echo "📦 Dependencies:"
    if [ -f "Package.resolved" ]; then
        echo "   SwiftPM packages:"
        xcodebuild -resolvePackageDependencies -scheme "$SCHEME" -quiet
        cat PulseFeed.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | grep -E "(\"identity\"|\"version\")" | sed 's/^/   /'
    else
        echo "   No Package.resolved found"
    fi
    echo ""
}

# Function to perform static analysis
run_static_analysis() {
    echo "🔬 Running Static Analysis..."
    
    # Create temp file for analysis output
    ANALYSIS_OUTPUT=$(mktemp)
    
    # Run analysis
    if xcodebuild analyze \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath ./DerivedData \
        -quiet 2>&1 | tee "$ANALYSIS_OUTPUT" | xcbeautify; then
        
        echo "✅ Static analysis passed!"
        
        # Check for analyzer warnings
        ANALYZER_WARNINGS=$(grep -c "analyzer warning:" "$ANALYSIS_OUTPUT" || true)
        if [ "$ANALYZER_WARNINGS" -gt 0 ]; then
            echo "⚠️  Found $ANALYZER_WARNINGS analyzer warnings:"
            grep "analyzer warning:" "$ANALYSIS_OUTPUT" | sort -u | head -5
        fi
    else
        echo "❌ Static analysis failed!"
        grep -E "error:|warning:" "$ANALYSIS_OUTPUT" | sort -u | head -10
        exit 1
    fi
    
    rm -f "$ANALYSIS_OUTPUT"
    echo ""
}

# Function to check code formatting
check_code_format() {
    echo "🎨 Code Format Check:"
    
    # Count Swift files
    SWIFT_FILES=$(find PulseFeed -name "*.swift" | wc -l)
    echo "   Swift files: $SWIFT_FILES"
    
    # Check for common issues
    echo "   Checking for common issues..."
    
    # Check for TODO/FIXME comments
    TODO_COUNT=$(grep -r "TODO\|FIXME" PulseFeed --include="*.swift" | wc -l || echo "0")
    if [ "$TODO_COUNT" -gt 0 ]; then
        echo "   📝 Found $TODO_COUNT TODO/FIXME comments"
    fi
    
    # Check for print statements
    PRINT_COUNT=$(grep -r "print(" PulseFeed --include="*.swift" | wc -l || echo "0")
    if [ "$PRINT_COUNT" -gt 0 ]; then
        echo "   🖨️  Found $PRINT_COUNT print statements"
    fi
    
    echo ""
}

# Function to check build configuration
check_build_config() {
    echo "🏗️  Build Configuration Check:"
    
    # Check for Debug vs Release differences
    echo "   Debug configuration:"
    xcodebuild -scheme "$SCHEME" -configuration Debug -showBuildSettings | grep -E "(OPTIMIZATION_LEVEL|DEBUG_INFORMATION_FORMAT)" | sed 's/^/      /'
    
    echo "   Release configuration:"
    xcodebuild -scheme "$SCHEME" -configuration Release -showBuildSettings | grep -E "(OPTIMIZATION_LEVEL|DEBUG_INFORMATION_FORMAT)" | sed 's/^/      /'
    
    echo ""
}

# Function to run all checks
run_all_checks() {
    check_swift_version
    check_build_settings
    check_dependencies
    run_static_analysis
    check_code_format
    check_build_config
    
    echo "🎯 Build Check Summary:"
    echo "   ✅ All checks completed"
    echo "   🔨 Ready to build: ./build.sh"
    echo "   🧪 Ready to test: ./test.sh"
}

# Main execution
case "$CHECK_TYPE" in
    "all")
        run_all_checks
        ;;
    "analyze")
        run_static_analysis
        ;;
    "swift")
        check_swift_version
        check_build_settings
        ;;
    "deps")
        check_dependencies
        ;;
    "format")
        check_code_format
        ;;
    "config")
        check_build_config
        ;;
    *)
        echo "❌ Unknown check type: $CHECK_TYPE"
        echo "Usage: ./build_check.sh [all|analyze|swift|deps|format|config]"
        exit 1
        ;;
esac

echo ""
echo "⏱️  Check completed in $(date -u '+%M:%S')"