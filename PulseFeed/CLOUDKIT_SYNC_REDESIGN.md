# CloudKit Sync Redesign Plan

## Problem Statement

The current CloudKit sync implementation has critical reliability issues:
- Articles marked as read on one device don't sync to other devices
- CloudKit frequently returns rate limiting errors ("Request Rate Limited")
- Data discrepancies: macOS has 6108 items but only 5984 sync to CloudKit
- Articles are lost during sync (e.g., "CloudKit MISSING fortnite-darth-vader")
- No recovery mechanism when CloudKit fails

## Root Causes

1. **Over-reliance on CloudKit**: The app treats CloudKit as the primary source of truth
2. **Aggressive syncing**: Too many sync operations cause rate limiting
3. **No local fallback**: When CloudKit fails, data is lost
4. **Incomplete error handling**: Rate limit errors aren't properly handled

## Proposed Solution: UserDefaults-First Architecture

### Core Principles

1. **UserDefaults as Primary Storage**: All read status operations write to UserDefaults first
2. **CloudKit as Backup**: CloudKit becomes a secondary sync mechanism
3. **Eventual Consistency**: Accept that CloudKit sync may be delayed
4. **Manual Sync Option**: Give users control when automatic sync fails

### Architecture Changes

#### 1. Immediate Local Storage
```swift
// When marking article as read/unread
markArticle(link: String, as isRead: Bool) {
    // 1. Always save to UserDefaults first
    saveToUserDefaults(link, isRead)
    
    // 2. Update UI immediately
    updateUI()
    
    // 3. Queue CloudKit sync
    queueCloudKitSync()
}
```

#### 2. CloudKit Sync Queue
- Implement a sync queue with exponential backoff
- Handle rate limiting with delays
- Batch operations to reduce API calls

#### 3. Sync Status Indicator
- Visual indicator showing sync status
- States: "Synced", "Syncing", "Sync Failed", "Offline"
- Tap for details or manual sync

#### 4. Manual Sync Button
- Settings option: "Force CloudKit Sync"
- Pulls all CloudKit data
- Merges with local UserDefaults
- Pushes complete merged set back to CloudKit

### Implementation Phases

#### Phase 1: Local-First Read Status (1 week)
- [ ] Modify `ReadStatusTracker` to always save to UserDefaults first
- [ ] Add queueing mechanism for CloudKit syncs
- [ ] Implement retry logic with exponential backoff
- [ ] Add comprehensive error logging

#### Phase 2: Sync Status UI (1 week)
- [ ] Add sync status indicator to home screen
- [ ] Implement sync status enum and tracking
- [ ] Create sync history log
- [ ] Add user notifications for sync failures

#### Phase 3: Manual Sync & Recovery (1 week)
- [ ] Add "Force Sync" button in settings
- [ ] Implement merge algorithm for conflicting data
- [ ] Add sync conflict resolution (prefer local or remote)
- [ ] Create backup/restore functionality

#### Phase 4: Optimization & Testing (1 week)
- [ ] Batch sync operations to reduce API calls
- [ ] Implement smart sync timing (when app is idle)
- [ ] Add unit tests for sync logic
- [ ] Performance testing with large datasets

### Technical Details

#### Sync State Management
```swift
enum SyncState {
    case synced
    case syncing
    case failed(Error)
    case offline
    case pending
}

class SyncManager {
    private var syncQueue: [SyncOperation] = []
    private var retryCount: [String: Int] = [:]
    private var lastSyncTime: Date?
    
    func queueSync(operation: SyncOperation) {
        syncQueue.append(operation)
        processSyncQueue()
    }
    
    func processSyncQueue() {
        // Implement with exponential backoff
    }
}
```

#### Rate Limit Handling
```swift
func handleCloudKitError(_ error: Error) {
    if let ckError = error as? CKError {
        switch ckError.code {
        case .requestRateLimited:
            let retryAfter = ckError.retryAfterSeconds ?? 5.0
            scheduleRetry(after: retryAfter)
        case .serviceUnavailable:
            scheduleRetry(after: 30.0)
        default:
            logError(error)
        }
    }
}
```

#### Merge Algorithm
```swift
func mergeReadStatus(local: Set<String>, cloud: Set<String>) -> Set<String> {
    // 1. Union of both sets (never lose data)
    var merged = local.union(cloud)
    
    // 2. Handle conflicts based on user preference
    if userPreference == .preferLocal {
        // Local changes take precedence
    } else if userPreference == .preferRecent {
        // Most recent change wins
    }
    
    return merged
}
```

### User Experience Improvements

1. **Immediate Feedback**: Articles marked as read update instantly
2. **Sync Status Visibility**: Users know when data is synced
3. **Manual Control**: Force sync option when needed
4. **Reliability**: Local storage ensures no data loss
5. **Transparency**: Clear sync status and error messages

### Migration Strategy

1. **Detect existing CloudKit data**
2. **Pull all CloudKit records**
3. **Merge with local UserDefaults**
4. **Save merged data to UserDefaults**
5. **Queue CloudKit update with merged data**
6. **Enable new sync system**

### Success Metrics

- Zero data loss for read status
- 99% sync success rate within 5 minutes
- Reduced CloudKit API calls by 50%
- User satisfaction improvement
- Decreased support requests for sync issues

### Rollback Plan

1. Keep old sync code behind feature flag
2. Monitor error rates and user feedback
3. Quick toggle to revert if issues arise
4. Gradual rollout to subset of users

### Timeline

- Week 1-2: Core implementation
- Week 3: UI and manual sync
- Week 4: Testing and optimization
- Week 5: Beta testing
- Week 6: Full rollout

### Future Enhancements

1. **Selective Sync**: Choose what to sync
2. **Compression**: Reduce CloudKit storage
3. **Conflict Resolution UI**: Let users resolve conflicts
4. **Export/Import**: Backup read status
5. **Cross-Platform Sync**: Support for Mac app