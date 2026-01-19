# Audio Level Dot Matrix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace horizontal bar visualization with center-out symmetric dot matrix in `AudioLevelBar`.

**Architecture:** Rewrite Canvas drawing to render 3 rows × 15 columns of circular dots that fill from center outward horizontally and bottom-up vertically. Remove `isVoiceDetected` parameter—color derives purely from position (green center → yellow mid → red edges).

**Tech Stack:** SwiftUI Canvas, TimelineView, Path(ellipseIn:)

---

## Task 1: Add Constants

**Files:**
- Modify: `/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2/Views/Components/LiveTranscriptView.swift`

**Step 1: Add Constants enum inside AudioLevelBar**

Find `struct AudioLevelBar: View {` (around line 209) and add the constants immediately after the struct declaration:

```swift
struct AudioLevelBar: View {
    // MARK: - Constants

    private enum Constants {
        // Grid dimensions
        static let rowCount = 3
        static let standardColumnCount = 15  // odd for center symmetry
        static let lowPowerColumnCount = 9   // odd for center symmetry
        static let dotDiameter: CGFloat = 6.0
        static let dotSpacing: CGFloat = 3.0
        static let rowSpacing: CGFloat = 3.0

        // Row activation thresholds (level required to light each row)
        static let midRowThreshold: Float = 0.33
        static let topRowThreshold: Float = 0.66

        // Color zone boundaries (normalized distance from center)
        static let yellowZoneStart: Float = 0.5
        static let redZoneStart: Float = 0.8

        // Inactive dot appearance
        static let inactiveOpacity: Double = 0.3
    }
```

**Step 2: Build to verify no syntax errors**

Run: `xcodebuild -scheme "Voice Note v2" -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "(error:|warning:.*AudioLevelBar|Build Succeeded)"`

Expected: `Build Succeeded`

**Step 3: Commit**

```bash
git add Voice\ Note\ v2/Views/Components/LiveTranscriptView.swift
git commit -m "feat(AudioLevelBar): add dot matrix constants"
```

---

## Task 2: Remove isVoiceDetected from AudioLevelBar

**Files:**
- Modify: `/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2/Views/Components/LiveTranscriptView.swift`

**Step 1: Remove the isVoiceDetected property**

Find and delete this line (around line 214):
```swift
    let isVoiceDetected: Bool
```

Change it to just have:
```swift
    /// Current audio level (0.0 to 1.0)
    let level: Float

    /// App settings for frame rate and bar count
    @Environment(\.appSettings) private var appSettings
```

**Step 2: Update barColor function to remove isVoiceDetected reference**

Find the `barColor` function (around line 246-260) and replace it with a placeholder that always returns green (we'll replace the whole thing in Task 3):

```swift
    private func barColor(for index: Int, isActive: Bool, barCount: Int) -> Color {
        if !isActive {
            return Color.gray.opacity(Constants.inactiveOpacity)
        }
        return .green  // Placeholder - will be replaced with dotColor
    }
```

**Step 3: Build (expect errors in call sites)**

Run: `xcodebuild -scheme "Voice Note v2" -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "(error:|Build Succeeded)"`

Expected: Errors about missing `isVoiceDetected` argument at call sites

---

## Task 3: Update Call Sites

**Files:**
- Modify: `/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2/Views/Components/LiveTranscriptView.swift`
- Modify: `/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2/Views/RecordingView.swift`

**Step 1: Update LiveRecordingControlsView struct**

Find `struct LiveRecordingControlsView` (around line 166) and remove `isVoiceDetected`:

Before:
```swift
struct LiveRecordingControlsView: View {
    let audioLevel: Float
    let isVoiceDetected: Bool
    let onStop: () -> Void
```

After:
```swift
struct LiveRecordingControlsView: View {
    let audioLevel: Float
    let onStop: () -> Void
```

**Step 2: Update AudioLevelBar call inside LiveRecordingControlsView**

Find line 174 and change:
```swift
            AudioLevelBar(level: audioLevel, isVoiceDetected: isVoiceDetected)
```

To:
```swift
            AudioLevelBar(level: audioLevel)
```

**Step 3: Update RecordingView.swift call site**

Find line 196-204 in RecordingView.swift:
```swift
            LiveRecordingControlsView(
                audioLevel: recordingManager.currentAudioLevel,
                isVoiceDetected: recordingManager.isVoiceDetected,
                onStop: {
```

Change to:
```swift
            LiveRecordingControlsView(
                audioLevel: recordingManager.currentAudioLevel,
                onStop: {
```

**Step 4: Update preview providers in LiveTranscriptView.swift**

Find the previews (around lines 274-300) and remove `isVoiceDetected`:

```swift
#Preview("With Transcript") {
    VStack {
        LiveTranscriptView(
            transcript: "This is a test transcript that shows how the live transcription looks during recording. It should auto-scroll as more text appears.",
            isRecording: true,
            duration: 45
        )
        .frame(height: 300)

        LiveRecordingControlsView(
            audioLevel: 0.6,
            onStop: {}
        )
        .frame(height: 200)
    }
    .padding()
}

#Preview("Recording Empty State") {
    VStack {
        LiveTranscriptView(
            transcript: "",
            isRecording: true,
            duration: 3
        )
        .frame(height: 300)

        LiveRecordingControlsView(
            audioLevel: 0.2,
            onStop: {}
        )
        .frame(height: 200)
    }
    .padding()
}
```

**Step 5: Build to verify**

Run: `xcodebuild -scheme "Voice Note v2" -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "(error:|warning:|Build Succeeded)"`

Expected: `Build Succeeded`

**Step 6: Commit**

```bash
git add Voice\ Note\ v2/Views/Components/LiveTranscriptView.swift Voice\ Note\ v2/Views/RecordingView.swift
git commit -m "refactor(AudioLevelBar): remove isVoiceDetected parameter"
```

---

## Task 4: Implement Dot Matrix Drawing Logic

**Files:**
- Modify: `/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2/Views/Components/LiveTranscriptView.swift`

**Step 1: Add helper functions after Constants enum**

Add these functions inside `AudioLevelBar` struct, after the Constants enum:

```swift
    // MARK: - Activation Logic

    /// Determines if a column should be lit based on center-out fill pattern.
    /// Center columns light first, edges require higher level.
    private func isColumnActive(column: Int, totalColumns: Int) -> Bool {
        let center = Float(totalColumns - 1) / 2.0
        let distanceFromCenter = abs(Float(column) - center)
        let maxDistance = center
        let normalizedDistance = distanceFromCenter / maxDistance  // 0.0 at center, 1.0 at edge

        // Invert: center requires level > 0, edges require level > 1.0
        // So center lights first, edges light last
        return level >= normalizedDistance
    }

    /// Returns how many rows should be lit (1-3) based on level.
    /// Bottom row lights first, top row requires highest level.
    private func activeRowCount() -> Int {
        if level >= Constants.topRowThreshold { return 3 }
        if level >= Constants.midRowThreshold { return 2 }
        return 1
    }

    /// Determines dot color based on horizontal distance from center.
    /// Center = green, mid = yellow, edges = red.
    private func dotColor(column: Int, totalColumns: Int, isActive: Bool) -> Color {
        if !isActive {
            return Color.gray.opacity(Constants.inactiveOpacity)
        }

        let center = Float(totalColumns - 1) / 2.0
        let distanceFromCenter = abs(Float(column) - center)
        let normalizedDistance = distanceFromCenter / center  // 0.0 to 1.0

        if normalizedDistance >= Constants.redZoneStart {
            return .red
        } else if normalizedDistance >= Constants.yellowZoneStart {
            return .yellow
        } else {
            return .green
        }
    }
```

**Step 2: Replace the body property with dot matrix rendering**

Replace the entire `var body: some View` property with:

```swift
    var body: some View {
        let interval = appSettings.frameRateInterval
        let columnCount = appSettings.lowPowerMode
            ? Constants.lowPowerColumnCount
            : Constants.standardColumnCount

        TimelineView(.animation(minimumInterval: interval)) { _ in
            Canvas { context, size in
                let totalHorizontalSpace = Constants.dotSpacing * CGFloat(columnCount - 1)
                let totalVerticalSpace = Constants.rowSpacing * CGFloat(Constants.rowCount - 1)

                // Calculate dot size to fit, capped at max diameter
                let availableWidth = size.width - totalHorizontalSpace
                let availableHeight = size.height - totalVerticalSpace
                let dotSize = min(
                    availableWidth / CGFloat(columnCount),
                    availableHeight / CGFloat(Constants.rowCount),
                    Constants.dotDiameter
                )

                // Center the grid horizontally
                let gridWidth = CGFloat(columnCount) * dotSize + totalHorizontalSpace
                let startX = (size.width - gridWidth) / 2

                // Center the grid vertically
                let gridHeight = CGFloat(Constants.rowCount) * dotSize + totalVerticalSpace
                let startY = (size.height - gridHeight) / 2

                let activeRows = activeRowCount()

                for row in 0..<Constants.rowCount {
                    for column in 0..<columnCount {
                        // Row 0 = bottom, row 2 = top
                        // Bottom rows light first, so check if row < activeRows
                        let rowActive = row < activeRows
                        let columnActive = isColumnActive(column: column, totalColumns: columnCount)
                        let isActive = rowActive && columnActive

                        let x = startX + CGFloat(column) * (dotSize + Constants.dotSpacing)
                        // Flip Y so row 0 is at bottom
                        let y = startY + CGFloat(Constants.rowCount - 1 - row) * (dotSize + Constants.rowSpacing)

                        let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                        let path = Path(ellipseIn: rect)

                        let color = dotColor(column: column, totalColumns: columnCount, isActive: isActive)
                        context.fill(path, with: .color(color))
                    }
                }
            }
            .drawingGroup()
        }
    }
```

**Step 3: Delete the old barColor function**

Remove the old `barColor` function since we now use `dotColor`.

**Step 4: Build to verify**

Run: `xcodebuild -scheme "Voice Note v2" -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "(error:|warning:.*LiveTranscript|Build Succeeded)"`

Expected: `Build Succeeded`

**Step 5: Commit**

```bash
git add Voice\ Note\ v2/Views/Components/LiveTranscriptView.swift
git commit -m "feat(AudioLevelBar): implement center-out dot matrix visualization"
```

---

## Task 5: Manual Visual Verification

**Step 1: Run the app in simulator**

Run: Open Xcode, select iPhone 16 simulator, Cmd+R to build and run

**Step 2: Test the visualization**

1. Navigate to recording view
2. Start a live transcription recording
3. Observe the dot matrix:
   - At silence: Only center columns, bottom row should be green
   - Speaking softly: More columns spread out, maybe 2 rows
   - Speaking loudly: Full spread reaching yellow/red edges, all 3 rows
   - The fill should be symmetric (mirrored left/right)

**Step 3: Test edge cases**

- Very quiet: Should see at minimum the center 1-2 dots on bottom row
- Very loud: All dots should light, edges should be red
- Transitions should feel smooth, not jumpy

**Step 4: Verify Low Power Mode**

1. Go to Settings > Battery > Low Power Mode (ON)
2. Return to app, start recording
3. Should see 9 columns instead of 15
4. Frame rate should be visibly slower but still smooth

---

## Task 6: Update Doc Comment

**Files:**
- Modify: `/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2/Views/Components/LiveTranscriptView.swift`

**Step 1: Update the struct doc comment**

Find the doc comment above `struct AudioLevelBar` and replace with:

```swift
/// Audio level visualization using a center-out symmetric dot matrix.
///
/// Visual behavior:
/// - 3 rows × 15 columns (9 in Low Power Mode)
/// - Fills from center outward horizontally as level increases
/// - Fills bottom-up vertically (bottom row = low, top row = loud)
/// - Color zones: green (center) → yellow (mid) → red (edges)
///
/// Performance:
/// - TimelineView provides 30/60fps update scheduling
/// - Canvas uses immediate-mode drawing with Metal compositing
/// - `.drawingGroup()` enables GPU acceleration
struct AudioLevelBar: View {
```

**Step 2: Build and commit**

```bash
xcodebuild -scheme "Voice Note v2" -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "(error:|Build Succeeded)"
git add Voice\ Note\ v2/Views/Components/LiveTranscriptView.swift
git commit -m "docs(AudioLevelBar): update doc comment for dot matrix"
```

---

## Verification Checklist

- [ ] Build succeeds with no warnings in modified files
- [ ] Dot matrix renders centered in the view
- [ ] Center columns light first at low levels
- [ ] Bottom row lights before middle and top rows
- [ ] Color gradient: green center → yellow mid → red edges
- [ ] Symmetric left/right fill pattern
- [ ] Low Power Mode shows 9 columns instead of 15
- [ ] No visual flickering or jumpiness during normal speech
- [ ] Inactive dots visible at 30% gray opacity
