# CloudKit Sync Technical Findings

**Date:** 2026-01-20
**Source:** Swiftloop review of Recording.swift, AppSettings.swift, DatabaseManager.swift
**Related:** 2026-01-20-macos-port-icloud-sync-design.md

## Summary

Code review identified two blockers and several recommendations for enabling SwiftData CloudKit sync.

---

## Blockers

### 1. `@Attribute(.unique)` Incompatible with CloudKit

**Problem:** All models use `@Attribute(.unique)` on `id: UUID`. CloudKit doesn't support unique constraints.

**Current code:**
```swift
@Model
final class Recording {
    @Attribute(.unique) var id: UUID  // ❌ CloudKit incompatible
}
```

**Impact:** SwiftData will fail to sync or throw errors when CloudKit is enabled.

**Status:** Needs resolution before Phase 2 (Sync)

---

### 2. Settings Architecture Incompatible with Sync

**Problem:** `AppSettings` uses `UserDefaults` for storage. UserDefaults doesn't sync via SwiftData CloudKit.

**Current code:**
```swift
@MainActor @Observable
final class AppSettings {
    var lowPowerMode: Bool {
        didSet { UserDefaults.standard.lowPowerMode = lowPowerMode }
    }
    // ... all settings in UserDefaults
}
```

**Impact:** New sync settings (audioSyncPolicy, retentionPolicy, etc.) won't sync across devices.

**Options:**
1. Migrate to SwiftData model (UserPreferences)
2. Use NSUbiquitousKeyValueStore (1MB limit, 1024 keys max)
3. Hybrid: SwiftData for sync-critical, UserDefaults for device-specific

**Status:** Needs resolution before Phase 2 (Sync)

---

## Recommendations

### High Confidence (Both Agents Agreed)

| Item | File | Action |
|------|------|--------|
| Remove `@Attribute(.unique)` | Recording.swift | Remove from all models |
| Settings migration | AppSettings.swift | Move to SwiftData or NSUbiquitousKeyValueStore |
| Add `sourceDevice` | Recording.swift | Add enum field |
| Add `isAudioSynced` | Recording.swift | Add Bool field |
| File path abstraction | Recording.swift | Create protocol for platform-specific paths |

### Medium Confidence

| Item | File | Action |
|------|------|--------|
| Test AttributedString sync | Recording.swift | Verify CloudKit handles it; fallback to String if not |
| Remove unused import | DatabaseManager.swift | Remove `import CoreData` |
| Consolidate UserDefaults keys | AppSettings.swift | Use typed accessors consistently |

---

## Apple Documentation Findings

### ModelConfiguration CloudKit

```swift
// Enable sync
let config = ModelConfiguration(
    schema: schema,
    url: storeURL,
    cloudKitDatabase: .automatic
)

// Disable sync
let config = ModelConfiguration(
    schema: schema,
    url: storeURL,
    cloudKitDatabase: .none
)
```

### CloudKit Schema Requirements

From Apple Developer Forums:
- **Relationships must be optional** ✅ (current code correct)
- **No unique constraints** ❌ (current code has @Attribute(.unique))
- **Deploy schema in CloudKit Console** after model changes

### Known Issues (iOS 26)

- BAD_REQUEST errors reported after iOS 26 update
- iOS 26.1 store file version mismatch errors
- Workaround: Deploy schema changes via CloudKit Console

---

## Current State Assessment

| Component | Sync Ready | Notes |
|-----------|------------|-------|
| Recording model | ⚠️ Partial | Remove .unique, add sourceDevice/isAudioSynced |
| Transcript model | ⚠️ Partial | Remove .unique, test AttributedString |
| ProcessedNote model | ⚠️ Partial | Remove .unique |
| Template model | ⚠️ Partial | Remove .unique |
| AppSettings | ❌ No | UserDefaults incompatible |
| DatabaseManager | ✅ Ready | Just flip .none to .automatic |
| Relationships | ✅ Ready | Already optional with cascade |

---

## Implementation Order

1. **P0:** Remove `@Attribute(.unique)` from all models
2. **P0:** Decide settings migration approach (SwiftData vs NSUbiquitousKeyValueStore)
3. **P1:** Add `sourceDevice` and `isAudioSynced` to Recording
4. **P1:** Test AttributedString CloudKit sync
5. **P2:** Abstract file paths for multiplatform
6. **P2:** Clean up minor issues (CoreData import, UserDefaults keys)

---

## Detailed Solutions (Swiftloop Analysis)

### Solution 1: Remove @Attribute(.unique)

**Recommendation:** Just remove it. No migration code needed.

**Rationale:**
- UUID collisions are statistically impossible (1 in 2^122)
- This is a schema *relaxation* — SwiftData handles automatically
- CloudKit doesn't support unique constraints
- Existing data remains intact

**Code Changes (4 files, 4 lines):**

```swift
// Recording.swift line 46
- @Attribute(.unique) var id: UUID
+ var id: UUID

// Transcript (same file, line ~93)
- @Attribute(.unique) var id: UUID
+ var id: UUID

// ProcessedNote (same file, line ~133)
- @Attribute(.unique) var id: UUID
+ var id: UUID

// Template.swift line 7
- @Attribute(.unique) var id: UUID
+ var id: UUID
```

**Risk Assessment:**
- Duplicate UUID risk: ~0% (astronomically unlikely)
- Data loss risk: None
- Migration effort: Zero (automatic)

---

### Solution 2: Settings Architecture — Hybrid Approach

**Recommendation:** Use `NSUbiquitousKeyValueStore` for synced settings + `UserDefaults` for device-local.

**Why not SwiftData for settings?**
- Settings are preferences, not data — different use case
- SwiftData singleton pattern is awkward (needs ModelContext everywhere)
- NSUbiquitousKeyValueStore is Apple's purpose-built solution for this
- Simpler: ~30 lines vs ~100+ for SwiftData approach

**Settings Classification:**

| Setting | Storage | Rationale |
|---------|---------|-----------|
| `audioSyncPolicy` | **iCloud KVS** | User's sync preference follows them |
| `retentionPolicy` | **iCloud KVS** | Data policy should be consistent |
| `isProUser` | **iCloud KVS** | Subscription status follows user |
| `autoCopyOnComplete` | **iCloud KVS** | User workflow preference |
| `recentClipsCount` | **iCloud KVS** | UI preference, sync-friendly |
| `lowPowerMode` | UserDefaults | Device battery varies |
| `showAudioVisualizer` | UserDefaults | Device performance varies |
| `audioVisualizerMonochrome` | UserDefaults | Per-device UI preference |
| `menuBarClickAction` | UserDefaults | macOS-only, device-specific |
| `globalHotkeyEnabled` | UserDefaults | Keyboard shortcuts are device-specific |

**Implementation:**

```swift
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Storage Backends
    private let syncedStore = NSUbiquitousKeyValueStore.default
    private let localStore = UserDefaults.standard

    // MARK: - Synced Settings (iCloud Key-Value Store)

    var audioSyncPolicy: AudioSyncPolicy {
        didSet {
            syncedStore.set(audioSyncPolicy.rawValue, forKey: "audioSyncPolicy")
            syncedStore.synchronize()
        }
    }

    var retentionPolicy: RetentionPolicy {
        didSet {
            syncedStore.set(retentionPolicy.rawValue, forKey: "retentionPolicy")
            syncedStore.synchronize()
        }
    }

    var isProUser: Bool {
        didSet {
            syncedStore.set(isProUser, forKey: "isProUser")
            syncedStore.synchronize()
        }
    }

    var autoCopyOnComplete: Bool {
        didSet {
            syncedStore.set(autoCopyOnComplete, forKey: "autoCopyOnComplete")
            syncedStore.synchronize()
        }
    }

    var recentClipsCount: Int {
        didSet {
            syncedStore.set(recentClipsCount, forKey: "recentClipsCount")
            syncedStore.synchronize()
        }
    }

    // MARK: - Device-Local Settings (UserDefaults)

    var lowPowerMode: Bool {
        didSet { localStore.lowPowerMode = lowPowerMode }
    }

    var showAudioVisualizer: Bool {
        didSet { localStore.set(showAudioVisualizer, forKey: "showAudioVisualizer") }
    }

    var audioVisualizerMonochrome: Bool {
        didSet { localStore.set(audioVisualizerMonochrome, forKey: "audioVisualizerMonochrome") }
    }

    #if os(macOS)
    var menuBarClickAction: MenuBarAction {
        didSet { localStore.set(menuBarClickAction.rawValue, forKey: "menuBarClickAction") }
    }

    var globalHotkeyEnabled: Bool {
        didSet { localStore.set(globalHotkeyEnabled, forKey: "globalHotkeyEnabled") }
    }
    #endif

    // MARK: - Initialization

    private init() {
        // Load synced settings
        self.audioSyncPolicy = AudioSyncPolicy(
            rawValue: syncedStore.string(forKey: "audioSyncPolicy") ?? ""
        ) ?? .never
        self.retentionPolicy = RetentionPolicy(
            rawValue: syncedStore.string(forKey: "retentionPolicy") ?? ""
        ) ?? .keepForever
        self.isProUser = syncedStore.bool(forKey: "isProUser")
        self.autoCopyOnComplete = syncedStore.bool(forKey: "autoCopyOnComplete")
        self.recentClipsCount = (syncedStore.object(forKey: "recentClipsCount") as? Int) ?? 5

        // Load device-local settings
        self.lowPowerMode = localStore.lowPowerMode
        self.showAudioVisualizer = localStore.object(forKey: "showAudioVisualizer") as? Bool ?? true
        self.audioVisualizerMonochrome = localStore.bool(forKey: "audioVisualizerMonochrome")

        #if os(macOS)
        self.menuBarClickAction = MenuBarAction(
            rawValue: localStore.string(forKey: "menuBarClickAction") ?? ""
        ) ?? .openMenu
        self.globalHotkeyEnabled = localStore.bool(forKey: "globalHotkeyEnabled")
        #endif

        // Listen for external changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: syncedStore
        )
    }

    @objc private func handleExternalChange(_ notification: Notification) {
        Task { @MainActor in
            // Reload synced values when another device changes them
            if let policy = syncedStore.string(forKey: "audioSyncPolicy") {
                self.audioSyncPolicy = AudioSyncPolicy(rawValue: policy) ?? .never
            }
            if let retention = syncedStore.string(forKey: "retentionPolicy") {
                self.retentionPolicy = RetentionPolicy(rawValue: retention) ?? .keepForever
            }
            self.isProUser = syncedStore.bool(forKey: "isProUser")
            self.autoCopyOnComplete = syncedStore.bool(forKey: "autoCopyOnComplete")
            self.recentClipsCount = (syncedStore.object(forKey: "recentClipsCount") as? Int) ?? 5
        }
    }

    // MARK: - Computed Properties (unchanged)

    var frameRateInterval: Double {
        AudioConstants.FrameRate.interval(lowPowerMode: lowPowerMode)
    }

    var frameRateCFInterval: CFAbsoluteTime {
        AudioConstants.FrameRate.cfInterval(lowPowerMode: lowPowerMode)
    }

    var levelBarCount: Int {
        AudioConstants.LevelBar.barCount(lowPowerMode: lowPowerMode)
    }
}

// MARK: - Supporting Enums

enum AudioSyncPolicy: String, Codable {
    case never
    case last7Days
    case last30Days
    case all
}

enum RetentionPolicy: String, Codable {
    case keepForever
    case deleteAfter7Days
    case deleteAfter30Days
    case deleteAfter90Days
    case keepTextDeleteAudio7Days
    case keepTextDeleteAudio30Days
}

#if os(macOS)
enum MenuBarAction: String, Codable {
    case openMenu
    case toggleRecording
}
#endif
```

**Migration from current UserDefaults:**

```swift
// Add to init() - one-time migration
private func migrateFromUserDefaults() {
    let migrationKey = "settings_migrated_to_icloud_v1"
    guard !localStore.bool(forKey: migrationKey) else { return }

    // Migrate isProUser to iCloud
    if localStore.object(forKey: "isProUser") != nil {
        syncedStore.set(localStore.bool(forKey: "isProUser"), forKey: "isProUser")
    }

    syncedStore.synchronize()
    localStore.set(true, forKey: migrationKey)
}
```

---

## Effort Estimate

| Task | Files | Lines | Time |
|------|-------|-------|------|
| Remove @Attribute(.unique) | 2 | 4 | 5 min |
| Update AppSettings for hybrid | 1 | ~80 | 30 min |
| Add enum types | 1 | ~20 | 10 min |
| Test sync behavior | — | — | 1 hr |
| **Total** | **4** | **~104** | **~2 hrs** |

---

## References

- [ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)
- [Syncing model data across devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [WWDC23: Dive deeper into SwiftData](https://developer.apple.com/videos/play/wwdc2023/10196/)
