# macOS Port & iCloud Sync Design

**Date:** 2026-01-20
**Status:** Draft
**Target:** macOS Tahoe 26+, iOS 26+

## Overview

Add iCloud sync between iOS and macOS versions of Voice Note, with a Mac-native app featuring menu bar quick-capture, floating HUD transcription panel, and clipboard history.

## Core Features

### 1. iCloud Sync
- Unified library across iOS and macOS
- Transcripts + metadata sync by default (lightweight)
- Audio file sync is user-configurable
- Device origin tracking (iOS vs Mac badges)

### 2. macOS Menu Bar App
- Quick capture from menu bar
- Floating HUD panel shows live transcription
- Clipboard history with search
- Global keyboard shortcut

### 3. Unified Library
- Tabs: All Notes / iOS / Mac
- Same recordings visible on both platforms
- Mac-native UI (sidebar, toolbar, keyboard navigation)

---

## Data Model Changes

### Recording Model Additions

```swift
// Add to Recording
var sourceDevice: SourceDevice  // .iOS or .mac
var isAudioSynced: Bool         // false if audio only exists on origin device

enum SourceDevice: String, Codable {
    case iOS
    case mac
}
```

### New Settings

```swift
// AppSettings additions
var audioSyncPolicy: AudioSyncPolicy      // .never, .last7Days, .last30Days, .all
var retentionPolicy: RetentionPolicy      // .keepForever, .deleteAfterDays(Int), .keepTextDeleteAudio(Int)
var menuBarClickAction: MenuBarAction     // .openMenu, .toggleRecording
var autoCopyOnComplete: Bool
var globalHotkeyEnabled: Bool
var globalHotkey: KeyboardShortcut?
var recentClipsCount: Int                 // default 5, max 15
```

### Sync Behavior
- Recording, Transcript, ProcessedNote sync via CloudKit (SwiftData native)
- Audio files stored in iCloud Drive separately, managed by AudioSyncService
- Retention settings synced via NSUbiquitousKeyValueStore

---

## macOS App Architecture

### App Structure
- **Menu bar agent** - NSStatusItem with dropdown, always running
- **Main window** - SwiftUI Window with sidebar navigation, launched on demand
- **Floating panel** - NSPanel (HUD style) for live transcription

### File Structure

```
VoiceNote-macOS/
├── App/
│   └── VoiceNoteMacApp.swift
├── MenuBar/
│   ├── MenuBarController.swift      // NSStatusItem management
│   ├── MenuBarDropdown.swift        // SwiftUI dropdown content
│   └── RecentClipsView.swift
├── FloatingPanel/
│   ├── TranscriptionPanel.swift     // NSPanel subclass (HUD style)
│   └── LiveTranscriptPanelView.swift
├── MainWindow/
│   ├── LibraryWindow.swift
│   ├── SidebarView.swift
│   └── RecordingListView.swift
└── Services/
    ├── MacAudioService.swift        // AVAudioEngine for Mac
    ├── MacTranscriptionService.swift
    └── GlobalHotkeyService.swift
```

### Shared Code (Multiplatform)
- Models (Recording, Transcript, ProcessedNote, Template)
- OnDeviceAIService (Foundation Models)
- TemplateManager
- DatabaseManager
- AppSettings (with platform-specific keys)

---

## Floating Transcription Panel (HUD)

### Visual Design
- Translucent vibrancy background (NSVisualEffectView, .hudWindow material)
- No title bar - custom drag region at top
- Rounded corners (12pt radius)
- Default size: 320w × 180h, resizable (min 240×120, max 600×400)
- Remembers position and size between sessions

### Layout

```
┌─────────────────────────────────┐
│  ═══  (drag grip)               │
├─────────────────────────────────┤
│                                 │
│  Live transcript text flows     │
│  here, auto-scrolls to bottom   │
│  as new words appear...         │
│                                 │
├─────────────────────────────────┤
│  ● 0:42        [Stop] [Copy]    │
└─────────────────────────────────┘
```

### Behaviors
- Floats above all windows (NSPanel with .floating level)
- Appears on recording start at last-used location
- Stays visible across Space/desktop switches (.canJoinAllSpaces)
- On stop: stays showing final transcript until dismissed
- Click outside doesn't dismiss

---

## Menu Bar Dropdown

### Contents
- Record / Stop button (prominent, at top)
- Search field (filters recent clips inline)
- Recent clips (last 5 by default, configurable)
- Divider
- Open Library (⌘L)
- Settings (⌘,)
- Quit

### Recent Clips Format

```
┌─────────────────────────────────────────┐
│ 🔍 Search clips...                      │
├─────────────────────────────────────────┤
│ "Remind me to call the dentist..."   📱 │
│ 2 min ago                               │
├─────────────────────────────────────────┤
│ "The API endpoint should accept..."  💻 │
│ 15 min ago                              │
└─────────────────────────────────────────┘
```

- Text preview on left (primary)
- Device icon on right (subtle)
- Single click copies full transcript

---

## iCloud Sync Architecture

### SwiftData CloudKit Sync
- Enable CloudKit in ModelConfiguration (change from .none to .automatic)
- All models sync automatically
- Conflict resolution: last-write-wins (SwiftData default)

### Audio Sync Service

```swift
class AudioSyncService {
    // iCloud Drive container: iCloud/com.yourapp.voicenote/Audio/

    func uploadAudioIfNeeded(_ recording: Recording)
    func downloadAudio(for recording: Recording) async throws -> URL
    func pruneAudioFiles(policy: AudioSyncPolicy)
    func isAudioAvailableLocally(_ recording: Recording) -> Bool
}
```

### Sync Flow - New Recording
1. Recording saved locally (SwiftData)
2. SwiftData syncs metadata to CloudKit (automatic)
3. AudioSyncService checks policy → uploads audio if allowed
4. Other device: receives Recording via SwiftData
5. Other device: shows "audio not synced" state if applicable

### Sync Flow - Audio on Demand
1. User taps "Download Audio"
2. AudioSyncService downloads from iCloud Drive
3. Update isAudioSynced = true locally
4. Playback enabled

---

## Main Window (Mac-Native)

### Sidebar Navigation
- All Notes
- iOS
- Mac
- ---
- Templates
- Settings

### Library View
- Full search across all recordings
- Sort by: Date (default), Duration, Title
- List view with expandable cards
- Keyboard navigable: ↑↓ select, Enter expand, ⌘C copy

### Copy Options (Detail View)
- Copy Transcript
- Copy Cleaned Transcript (if available)
- Copy [Template Name] (for each processed template)

---

## Settings

### Shared Settings (Sync via iCloud)
- Audio sync policy: Never / Last 7 days / Last 30 days / All
- Retention policy: Keep forever / Delete after X days / Keep text, delete audio
- Recent clips count: 5 (default) / 10 / 15
- Default template

### macOS-Only Settings
- Menu bar click action: Open menu (default) / Toggle recording
- Auto-copy on complete: Off (default) / On
- Global hotkey: Enabled/disabled + key combo picker
- Show in Dock: When window open (default) / Always / Never
- Floating panel: Show live transcript (default) / Minimal indicator

---

## Implementation Phases

### Phase 1 - Foundation
- macOS app skeleton (menu bar + main window)
- Floating HUD panel with live transcription
- Basic recording flow (start/stop from menu bar)
- Local-only on Mac (no sync yet)
- Copy transcript on complete

### Phase 2 - Sync
- Enable CloudKit sync for SwiftData models
- Add sourceDevice field, migrate existing iOS recordings
- Device origin badges in both apps
- Library tabs (All / iOS / Mac)
- Settings sync via NSUbiquitousKeyValueStore

### Phase 3 - Audio Sync
- AudioSyncService implementation
- iCloud Drive audio storage
- Sync policy settings
- Download on demand UI

### Phase 4 - Polish
- Global hotkey support
- Configurable menu bar click behavior
- Auto-copy options
- Retention policy enforcement
- Mac-native keyboard navigation throughout

---

## Out of Scope (Future)

- Meeting/system audio transcription (requires Screen Recording permission)
- Favorites/pinning
- Text entry (non-voice clips)
- Groq cloud templates
- Minimal indicator mode for HUD

---

## Open Questions

1. CloudKit container naming - use existing app bundle ID or new shared container?
2. Migration strategy for existing iOS recordings (set sourceDevice = .iOS)
3. Template sync - sync user-created templates only, or built-ins too?
