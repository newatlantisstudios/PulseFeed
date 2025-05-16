# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PulseFeed is an iOS RSS feed reader application that allows users to:
- Subscribe to and manage RSS feeds
- Read articles with full-text extraction capabilities
- Sync read status across devices using CloudKit
- Organize feeds into folders and smart folders
- Search and filter articles

## Architecture

### Core Components

1. **Feed Management**
   - `RSSFeed`: Model for RSS feed subscriptions
   - `RSSItem`: Model for individual articles
   - `FeedFolder`/`SmartFolder`: Organizational structures
   - `RSSParser`: Feed parsing using SwiftSoup

2. **Sync System**
   - `StorageManager`: Handles UserDefaults/CloudKit storage
   - `BackgroundRefreshManager`: Manages background feed updates
   - CloudKit integration for cross-device sync

3. **UI Architecture**
   - `HomeFeedViewController`: Main feed list view (split into extensions)
   - `ArticleReaderViewController`: Article reading interface
   - Settings screens for configuration

4. **Read Status Tracking**
   - `ReadStatusTracker`: Manages read/unread states
   - `ReadingProgress`: Tracks reading position within articles
   - Sync between UserDefaults and CloudKit

## Build Commands

```bash
# Standard debug build
./build.sh

# Verbose build for debugging
./build.sh verbose

# Release build
./build.sh release

# Quick build (minimal output)
./quick_build.sh

# Watch mode (auto-rebuild on file changes)
./quick_build.sh watch

# Run tests
./test.sh

# Run specific tests
./test.sh MyTestClass

# Check for build errors/warnings
./build.sh check

# Clean build
./build.sh clean
```

## Development Tasks

### Linting and Type Checking
```bash
# Check for build issues
./build_check.sh

# Run static analysis
./build_check.sh analyze

# Check Swift version
./build_check.sh swift
```

### Testing
```bash
# Run all tests
./test.sh

# Run with coverage
./test.sh coverage

# Run specific test
./test.sh TestClassName
```

## Key Implementation Notes

### CloudKit Sync Issues
The project is undergoing a CloudKit sync redesign (see CLOUDKIT_SYNC_REDESIGN.md) to address:
- Rate limiting issues
- Data loss during sync
- Sync reliability problems

Key changes planned:
- UserDefaults as primary storage
- CloudKit as secondary backup
- Eventual consistency model
- Manual sync options

### Background Refresh
- Uses BGTaskScheduler for periodic feed updates
- Configured in Info.plist with identifier: `com.pulsefeed.refreshFeeds`
- Handles both fetch and processing background modes

### Dependencies
- SwiftSoup: HTML parsing for feed content extraction
- StoreKit: In-app purchases/tips

### Storage Methods
- UserDefaults: Local storage for settings and read status
- CloudKit: Cross-device sync (when enabled)
- Method switching handled by `StorageManager.shared.method`

## Build Configuration

- Xcode project format: Modern (v77)
- Deployment target: iOS (check project.pbxproj for version)
- Swift version: Latest (check with `./build_check.sh swift`)
- Scheme: PulseFeed

## Debugging Tips

- Check sync_logs.txt for CloudKit sync issues
- Use build_errors.txt for build problems
- Enable verbose logging with DEBUG prints throughout the codebase
- Background refresh logs available in BackgroundRefreshManager

## Common Workflows

1. **Fix Sync Issues**: Review CLOUDKIT_SYNC_REDESIGN.md and implement UserDefaults-first approach
2. **Add New Feed Features**: Extend RSSFeed model and update HomeFeedViewController
3. **Improve Article Reading**: Modify ArticleReaderViewController and ContentExtractor
4. **Debug Background Refresh**: Check BackgroundRefreshManager and Info.plist configuration