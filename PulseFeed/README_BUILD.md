# PulseFeed Build Scripts

This directory contains several build scripts that use `xcbeautify` for cleaner output and support quiet mode for faster builds.

## Prerequisites

- Xcode (latest version recommended)
- xcbeautify: `brew install xcbeautify`
- fswatch (optional, for watch mode): `brew install fswatch`

## Available Scripts

### 1. build.sh - Main Build Script
The primary build script with multiple options:

```bash
./build.sh              # Default debug build with quiet output
./build.sh verbose      # Verbose build without beautify  
./build.sh release      # Release build with quiet output
./build.sh clean        # Clean build folder
./build.sh check        # Build and check for errors/warnings
```

Features:
- Uses xcbeautify for clean output
- Quiet mode by default for faster builds
- Error/warning detection and reporting
- Build time tracking

### 2. test.sh - Test Runner
Run unit tests with various options:

```bash
./test.sh               # Run all tests with quiet output
./test.sh verbose       # Verbose test output
./test.sh MyTestClass   # Run specific test class
./test.sh coverage      # Run tests with coverage report
```

Features:
- Automatic simulator selection
- Test summary reporting
- Code coverage analysis
- Specific test targeting

### 3. build_check.sh - Build Analysis
Comprehensive build environment checking:

```bash
./build_check.sh            # Run all checks
./build_check.sh analyze    # Run static analysis only
./build_check.sh swift      # Check Swift version and settings
./build_check.sh deps       # Check dependencies
./build_check.sh format     # Check code formatting
./build_check.sh config     # Check build configurations
```

Features:
- Static code analysis
- Dependency verification
- Code quality checks (TODOs, print statements)
- Build configuration comparison

### 4. quick_build.sh - Ultra-Fast Builds
Minimal output build script for development:

```bash
./quick_build.sh        # Ultra-quiet build, shows only errors
./quick_build.sh watch  # Watch mode - rebuilds on file changes
```

Features:
- Minimal console output
- File watch mode with auto-rebuild
- Fastest possible feedback loop

## Output Examples

### Standard Build Output
```
🔨 Building PulseFeed (Debug)...
📍 Project: /Users/x/Documents/GitHub/PulseFeed/PulseFeed

▸ Compiling AppDelegate.swift
▸ Compiling SceneDelegate.swift
▸ Linking PulseFeed
▸ Copying Info.plist
▸ Processing assets
✅ Build succeeded!

⏱️  Build completed in 00:42
```

### Error Detection Output
```
🔨 Building PulseFeed (Debug)...
📍 Project: /Users/x/Documents/GitHub/PulseFeed/PulseFeed

❌ Build failed!

Errors:
AppDelegate.swift:23: error: cannot find 'unknownFunction' in scope
SceneDelegate.swift:45: error: missing return in function

⚠️  Found 3 warnings
```

### Quick Build Output
```
🚀 Building... ✅
💨 Done in 00:15
```

## Best Practices

1. **Development**: Use `./quick_build.sh watch` for rapid iteration
2. **Pre-commit**: Run `./build.sh check` to catch issues early
3. **CI/CD**: Use `./build.sh release` for production builds
4. **Testing**: Run `./test.sh coverage` periodically to monitor test coverage
5. **Troubleshooting**: Use `./build.sh verbose` when debugging build issues

## Customization

All scripts can be modified to suit your workflow:
- Change default configurations in script headers
- Add custom build phases or checks
- Integrate with other tools in your pipeline

## Troubleshooting

### xcbeautify not found
Install with: `brew install xcbeautify`

### Build fails silently
Run with verbose mode: `./build.sh verbose`

### Scripts not executable
Make executable: `chmod +x *.sh`