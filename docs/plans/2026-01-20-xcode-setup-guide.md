# Xcode Setup Guide: macOS Target + iCloud Sync

**Date:** 2026-01-20
**Time Required:** ~15 minutes
**Prerequisites:** Apple Developer account with active membership

---

## Overview

This guide covers the one-time Xcode setup needed for:
1. iCloud sync (CloudKit + Key-Value Storage)
2. macOS app target

After this setup, all further development can be done outside Xcode.

---

## Part 1: Enable iCloud for iOS Target

### Step 1: Open Project
```
Open: Voice Note v2/Voice Note v2.xcodeproj
```

### Step 2: Select iOS Target
- In the project navigator (left sidebar), click the project file (blue icon)
- Under "TARGETS", select "Voice Note v2" (the iOS app)

### Step 3: Add iCloud Capability
1. Click the **"Signing & Capabilities"** tab
2. Click **"+ Capability"** button (top left of the editor)
3. Search for **"iCloud"** and double-click to add

### Step 4: Configure iCloud Services
In the iCloud capability section that appears:

- [x] **Key-value storage** — Check this box
- [x] **CloudKit** — Check this box
- [ ] iCloud Documents — Leave unchecked (not needed)

### Step 5: Create/Select CloudKit Container
1. Under "Containers", click the **"+"** button
2. Enter container identifier: `iCloud.com.YOURBUNDLEID.voicenote`
   - Replace YOURBUNDLEID with your actual bundle identifier
   - Example: `iCloud.com.example.voicenote`
3. Click "OK"
4. Make sure the new container is checked ✓

### Step 6: Verify Entitlements File Created
Xcode should have created: `Voice Note v2.entitlements`

Check the project navigator - you should see a new `.entitlements` file.

---

## Part 2: Add macOS Target

### Step 1: Create New Target
1. Menu: **File → New → Target...**
2. Select **macOS** tab at the top
3. Choose **"App"** template
4. Click "Next"

### Step 2: Configure macOS Target
Fill in the form:

| Field | Value |
|-------|-------|
| Product Name | `Voice Note Mac` |
| Team | (Your team) |
| Organization Identifier | (Same as iOS app) |
| Bundle Identifier | `com.YOURBUNDLEID.voicenote.mac` |
| Interface | **SwiftUI** |
| Language | **Swift** |
| Storage | **None** (we'll use existing SwiftData) |
| Include Tests | Optional |

Click "Finish"

### Step 3: Add iCloud to macOS Target
1. Select the new "Voice Note Mac" target
2. Go to **"Signing & Capabilities"** tab
3. Click **"+ Capability"**
4. Add **"iCloud"**
5. Configure identically to iOS:
   - [x] Key-value storage
   - [x] CloudKit
   - Select the **same container** as iOS (`iCloud.com.YOURBUNDLEID.voicenote`)

### Step 4: Set Deployment Target
1. Still in "Voice Note Mac" target settings
2. Go to **"General"** tab
3. Set **Minimum Deployments → macOS: 26.0**

### Step 5: Add Shared Files to macOS Target
In the project navigator, select these folders/files and in the File Inspector (right panel), check "Voice Note Mac" under Target Membership:

**Models (share all):**
- [ ] Voice Note v2 (iOS)
- [x] Voice Note Mac

```
Models/
├── Recording.swift
├── Template.swift
└── GenerableTemplates.swift
```

**Services (share most):**
```
Services/
├── RecordingManager.swift      ← Share
├── TemplateManager.swift       ← Share
├── OnDeviceAIService.swift     ← Share
├── DatabaseManager.swift       ← Share
├── LiveAudioService.swift      ← Platform-specific (may need #if os())
└── UnifiedTranscriptionService.swift ← Platform-specific
```

**Utilities (share all):**
```
Utilities/
├── AppSettings.swift           ← Share
├── AudioConstants.swift        ← Share
└── DatabaseManager.swift       ← Share
```

---

## Part 3: Verify Setup

### Check 1: Entitlements Files Exist
You should now have:
```
Voice Note v2/
├── Voice Note v2.entitlements        ← iOS
└── Voice Note Mac.entitlements       ← macOS (or similar name)
```

### Check 2: Build Both Targets
```bash
# Build iOS
xcodebuild -scheme "Voice Note v2" -destination "generic/platform=iOS" build

# Build macOS
xcodebuild -scheme "Voice Note Mac" -destination "generic/platform=macOS" build
```

### Check 3: CloudKit Dashboard
1. Go to: https://icloud.developer.apple.com/
2. Sign in with your Apple Developer account
3. Select your container
4. Verify it appears and is accessible

---

## Part 4: Post-Setup Code Changes

After Xcode setup, make these code changes (can be done outside Xcode):

### 4.1 Remove @Attribute(.unique)

Edit `Models/Recording.swift`:
```swift
// Line 46 - Remove @Attribute(.unique)
var id: UUID  // Was: @Attribute(.unique) var id: UUID

// Same for Transcript (~line 93), ProcessedNote (~line 133)
```

Edit `Models/Template.swift`:
```swift
// Line 7 - Remove @Attribute(.unique)
var id: UUID  // Was: @Attribute(.unique) var id: UUID
```

### 4.2 Add Source Device Field

Edit `Models/Recording.swift`, add after `audioFileName`:
```swift
var sourceDevice: SourceDevice = .iOS
var isAudioSynced: Bool = false

enum SourceDevice: String, Codable {
    case iOS
    case mac
}
```

### 4.3 Enable CloudKit Sync

Edit `Utilities/DatabaseManager.swift` or wherever ModelConfiguration is created:
```swift
// Change from:
cloudKitDatabase: .none

// To:
cloudKitDatabase: .automatic
```

### 4.4 Update AppSettings

See `docs/plans/2026-01-20-cloudkit-sync-technical-findings.md` for full implementation of hybrid settings storage.

---

## Entitlements File Reference

After setup, your entitlements should look like this:

**Voice Note v2.entitlements (iOS):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.YOURBUNDLEID.voicenote</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)com.YOURBUNDLEID.voicenote</string>
</dict>
</plist>
```

**Voice Note Mac.entitlements (macOS):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.YOURBUNDLEID.voicenote</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)com.YOURBUNDLEID.voicenote</string>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

---

## Troubleshooting

### "Container not found" error
- Go to CloudKit Dashboard and verify container exists
- Make sure you're signed into the same iCloud account on device/simulator
- Try: Product → Clean Build Folder, then rebuild

### "Entitlements missing" error
- Verify the entitlements file is listed in Build Settings → Code Signing Entitlements
- Check that the file path is correct (no typos)

### Sync not working
1. Check device is signed into iCloud
2. Check iCloud Drive is enabled for the app
3. In CloudKit Dashboard, click "Deploy Schema Changes" (bottom left)
4. Wait 1-2 minutes, data sometimes takes time to propagate

### macOS app won't build
- Verify deployment target is macOS 26.0+
- Check that shared files have macOS target membership
- Some iOS-specific APIs need `#if os(iOS)` guards

---

## CLI Commands Reference

```bash
# List available schemes
xcodebuild -list

# Build iOS for simulator
xcodebuild -scheme "Voice Note v2" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  build

# Build macOS
xcodebuild -scheme "Voice Note Mac" \
  -destination "platform=macOS" \
  build

# Run iOS tests
xcodebuild test -scheme "Voice Note v2" \
  -destination "platform=iOS Simulator,name=iPhone 16"

# Archive for distribution
xcodebuild archive -scheme "Voice Note v2" \
  -archivePath ./build/VoiceNote.xcarchive
```

---

## Next Steps After Setup

1. ✅ Xcode setup complete
2. → Make code changes (models, settings) - see technical findings doc
3. → Create macOS-specific views (MenuBar, FloatingPanel)
4. → Test sync between iOS simulator and Mac
5. → Deploy schema to CloudKit production before TestFlight

---

## Related Documents

- `2026-01-20-macos-port-icloud-sync-design.md` — Full feature design
- `2026-01-20-cloudkit-sync-technical-findings.md` — Code changes needed
