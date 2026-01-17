import SwiftUI
import SwiftData

// MARK: - Design Tokens
// Single source of truth for all spacing, sizing, and styling values.
// Enables precise communication: "use .sm (8pt)" instead of "a little smaller"

/// Spacing tokens based on 4pt grid system
enum Spacing {
    /// 4pt - Tight internal spacing (icon-to-text, compact lists)
    static let xs: CGFloat = 4
    /// 8pt - Standard internal spacing (button padding, list item gaps)
    static let sm: CGFloat = 8
    /// 16pt - Standard external spacing (section padding, card margins)
    static let md: CGFloat = 16
    /// 24pt - Section separation (between major UI groups)
    static let lg: CGFloat = 24
    /// 32pt - Major section separation (screen-level divisions)
    static let xl: CGFloat = 32
    /// 40pt - Extra large (bottom safe area, major gutters)
    static let xxl: CGFloat = 40
}

/// Corner radius tokens
enum Radius {
    /// 8pt - Small elements (buttons, chips, small cards)
    static let sm: CGFloat = 8
    /// 12pt - Medium containers (cards, input fields)
    static let md: CGFloat = 12
    /// 20pt - Large containers (modal sheets, transcript box)
    static let lg: CGFloat = 20
    /// 24pt - Extra large (full-screen overlays)
    static let xl: CGFloat = 24
}

/// Component sizing tokens
enum ComponentSize {
    /// 44pt - Minimum touch target (Apple HIG requirement)
    static let minTouchTarget: CGFloat = 44
    /// 72pt - Large button (stop recording button)
    static let largeButton: CGFloat = 72
    /// 28pt - Icon inside large button
    static let buttonIcon: CGFloat = 28
}

// MARK: - Debug Utilities
// Conditional compilation ensures these never ship in production.

extension View {
    /// Add a colored border to visualize view bounds (DEBUG only)
    func debugBorder(_ color: Color = .red) -> some View {
        #if DEBUG
        self.border(color, width: 1)
        #else
        self
        #endif
    }

    /// Add a colored background to visualize view area (DEBUG only)
    func debugBackground(_ color: Color = .blue.opacity(0.2)) -> some View {
        #if DEBUG
        self.background(color)
        #else
        self
        #endif
    }

    /// Print view size to console when layout changes (DEBUG only)
    func debugSize(_ label: String) -> some View {
        #if DEBUG
        self.background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    print("[\(label)] size: \(geo.size.width) x \(geo.size.height)")
                }
            }
        )
        #else
        self
        #endif
    }
}

// MARK: - Layout Helpers

extension View {
    /// Apply standard card styling with consistent radius and padding
    func cardStyle() -> some View {
        self
            .padding(Spacing.md)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Ensure minimum touch target size (44pt x 44pt per Apple HIG)
    func ensureTouchTarget() -> some View {
        self.frame(minWidth: ComponentSize.minTouchTarget,
                   minHeight: ComponentSize.minTouchTarget)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var recordingManager = RecordingManager()
    @Environment(\.modelContext) private var modelContext
    @State private var pendingTemplateId: String? = nil
    @AppStorage("favoriteTemplateId") private var favoriteTemplateIdString: String = ""
    
    // Computed property to handle UUID conversion
    private var favoriteTemplateId: UUID? {
        if favoriteTemplateIdString.isEmpty {
            // Default to brainstorm template
            return UUID(uuidString: "brainstorm") // This will be nil, handled below
        }
        return UUID(uuidString: favoriteTemplateIdString)
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Voice Note")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.primary, Color.primary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text("Record, transcribe, transform.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func firstRecordingCard(_ recording: Recording) -> some View {
        Button(action: {
            coordinator.showRecordingDetail(recording)
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Large quotation mark
                Text("\u{201C}")  // Left double quotation mark
                    .font(.system(size: 36, weight: .light, design: .serif))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, -8)
                
                // Main content
                VStack(alignment: .leading, spacing: 8) {
                    // Title if available
                    if let aiTitle = recording.transcript?.aiTitle {
                        Text(aiTitle)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    
                    // Duration badge
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text(formatDuration(recording.duration))
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    
                    // Transcript text
                    Group {
                        if let transcript = recording.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                           !transcript.isEmpty {
                            Text(getDisplayText(for: transcript, with: recording.transcript?.aiTitle))
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(recording.transcript?.aiTitle != nil ? .secondary : .primary)
                                .lineLimit(recording.transcript?.aiTitle != nil ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text("Transcribing...")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    
                    // Date
                    Text(formatRelativeDate(recording.createdAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Favorite template button
                if favoriteTemplateId != nil {
                    favoriteTemplateButton(for: recording)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    @ViewBuilder
    private func favoriteTemplateButton(for recording: Recording) -> some View {
        Button(action: {
            applyFavoriteTemplate(to: recording)
        }) {
            HStack(spacing: 4) {
                if let templateName = getFavoriteTemplateName() {
                    Image(systemName: templateIcon(for: templateName))
                        .font(.system(size: 14))
                    Text(templateName)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                    Text("Template")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.15))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var recentRecordingsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                // Add leading spacer to align with content padding
                Color.clear.frame(width: 0)

                // Show first 3 recordings
                if !recordingManager.recentRecordings.isEmpty {
                    ForEach(Array(recordingManager.recentRecordings.prefix(3).enumerated()), id: \.element.id) { index, recording in
                        RecentRecordingCard(recording: recording) {
                            coordinator.showRecordingDetail(recording)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                } else {
                    // Empty state placeholder card
                    emptyStateCard
                }

                // Add trailing spacer for padding
                Color.clear.frame(width: Spacing.md)
            }
            .padding(.horizontal, 1)  // Prevent clipping
        }
    }
    
    @ViewBuilder
    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mic")
                    .foregroundColor(.gray)
                Text("--:--")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Text("Record a note")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .lineLimit(2)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(10)
        .frame(width: 120, height: 120)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var floatingLibraryButton: some View {
        Button(action: {
            coordinator.showLibrary()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Text("Library")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 64, height: 64)
            .background(Color.blue)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Recent header
            Text("Recent")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            // Horizontal scroll with 3 cards
            recentRecordingsScroll
                .padding(.horizontal, -16) // Offset parent padding
        }
        .animation(.easeInOut(duration: 0.3), value: recordingManager.recentRecordings)
    }
    
    @ViewBuilder
    private var recordingInterface: some View {
        VStack(spacing: 16) {
            // Check if we're recording with live transcription
            if recordingManager.recordingState == .recording && recordingManager.isUsingLiveTranscription {
                // Live transcription UI
                liveTranscriptionInterface
            } else {
                // Standard recording UI
                standardRecordingInterface
            }
        }
    }

    /// Standard recording interface (idle, processing, or recording without live transcription)
    @ViewBuilder
    private var standardRecordingInterface: some View {
        VStack(spacing: 16) {
            // Timer area - fixed height
            VStack(spacing: 8) {
                if recordingManager.recordingState == .recording {
                    RecordingDisplay(
                        duration: recordingManager.currentDuration,
                        isRecording: true
                    )
                }
            }
            .frame(height: 40) // Fixed height whether timer shows or not

            // Microphone source indicator only - reduced height
            VStack {
                if recordingManager.recordingState == .recording {
                    HStack(spacing: 4) {
                        Image(systemName: microphoneIcon(for: recordingManager.currentInputDevice))
                            .font(.system(size: 10))
                        Text(recordingManager.currentInputDevice)
                            .font(.system(.caption2, design: .rounded))
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .frame(height: 16)
            .animation(.easeInOut(duration: 0.25), value: recordingManager.recordingState)
            .animation(.easeInOut(duration: 0.25), value: recordingManager.currentInputDevice)

            // BUTTON AND LEVELS - Fixed position, never moves
            HStack(alignment: .center, spacing: 24) {
                // Left audio levels
                AudioLevelVisualizer(
                    audioLevel: recordingManager.currentAudioLevel,
                    isRecording: recordingManager.recordingState == .recording,
                    isVoiceDetected: recordingManager.isVoiceDetected
                )

                // MAIN RECORDING BUTTON - NEVER MOVES
                RecordButton(
                    state: recordingManager.recordingState,
                    action: {
                        Task {
                            await recordingManager.toggleRecording()
                        }
                    }
                )

                // Right audio levels
                AudioLevelVisualizer(
                    audioLevel: recordingManager.currentAudioLevel,
                    isRecording: recordingManager.recordingState == .recording,
                    isVoiceDetected: recordingManager.isVoiceDetected
                )
            }

            // Status text - fixed height
            VStack {
                if !recordingManager.statusText.isEmpty {
                    Text(recordingManager.statusText)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 20) // Fixed height whether status shows or not
        }
    }

    /// Live transcription interface (recording with iOS 26+ SpeechAnalyzer)
    @ViewBuilder
    private var liveTranscriptionInterface: some View {
        VStack(alignment: .center, spacing: Spacing.md) {
            // Microphone source indicator
            HStack(alignment: .center, spacing: Spacing.xs) {
                Image(systemName: microphoneIcon(for: recordingManager.currentInputDevice))
                    .font(.system(size: 10))
                Text(recordingManager.currentInputDevice)
                    .font(.system(.caption2, design: .rounded))
            }
            .foregroundColor(.secondary.opacity(0.8))
            .debugBorder(.gray)
            .debugSize("MicIndicator")

            // Live transcript view
            // Access liveTranscriptionService.displayText directly so SwiftUI can track
            // the @Observable dependency (computed properties don't propagate observation)
            LiveTranscriptView(
                transcript: recordingManager.liveTranscriptionService.displayText,
                isRecording: true,
                duration: recordingManager.currentDuration
            )
            .frame(maxHeight: 280)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .opacity
            ))

            // Recording controls
            LiveRecordingControlsView(
                audioLevel: recordingManager.currentAudioLevel,
                isVoiceDetected: recordingManager.isVoiceDetected,
                onStop: {
                    Task {
                        await recordingManager.toggleRecording()
                    }
                }
            )
            .frame(height: 140)
        }
        .debugBorder(.red)
        .debugSize("LiveTranscriptionInterface")
        .animation(.easeInOut(duration: 0.3), value: recordingManager.isUsingLiveTranscription)
    }
    
    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.bottom, Spacing.md)

                // Recording interface - gets most space
                recordingInterface
                    .frame(minHeight: 300)
                    .frame(maxHeight: .infinity)

                // Recent Recordings Section - capped height
                recentRecordingsSection
                    .padding(.top, Spacing.md)
                    .frame(maxHeight: 180)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .bottomTrailing) {
            floatingLibraryButton
        }
        .sheet(item: $coordinator.activeSheet) { sheet in
            switch sheet {
            case .library:
                LibraryView(recordingManager: recordingManager)
            case .settings:
                SettingsView()
            case .templatePicker(let recording):
                TemplatePickerView(recording: recording) { template in
                    if let recording = recording {
                        Task {
                            try await recordingManager.processTemplate(template, for: recording)
                        }
                    }
                }
            case .recordingDetail(let recording):
                RecordingDetailView(recording: recording)
            }
        }
        .alert("Permission Required", isPresented: $coordinator.showPermissionAlert) {
            Button("Settings") {
                coordinator.openSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Voice Note needs microphone access to record audio. Please enable it in Settings.")
        }
        .alert("Transcription Failed", isPresented: $recordingManager.showFailedTranscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(recordingManager.failedTranscriptionMessage)
        }
        .onAppear {
            recordingManager.configure(with: modelContext)
            recordingManager.prewarmTranscription()  // Pre-download assets at launch
        }
        .onChange(of: recordingManager.lastRecordingId) { oldValue, newValue in
            if let recordingId = newValue,
               let templateId = pendingTemplateId,
               let recording = recordingManager.recentRecordings.first(where: { $0.id == recordingId }) {
                // Clear pending template
                pendingTemplateId = nil
                
                // Apply the template after a short delay to ensure transcription is ready
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    // Find the template
                    let descriptor = FetchDescriptor<Template>(
                        predicate: #Predicate { template in
                            template.id.uuidString == templateId
                        }
                    )
                    
                    if let templates = try? modelContext.fetch(descriptor),
                       let template = templates.first {
                        try? await recordingManager.processTemplate(template, for: recording)
                        
                        // Show the recording detail
                        coordinator.showRecordingDetail(recording)
                    }
                }
            }
        }
    }
    
    // Helper functions for stable hint text
    private func applyFavoriteTemplate(to recording: Recording) {
        guard let favoriteId = favoriteTemplateId else {
            // If no favorite set, try to find brainstorm template
            let templates = try? modelContext.fetch(FetchDescriptor<Template>())
            if let brainstormTemplate = templates?.first(where: { $0.name.lowercased().contains("brainstorm") }) {
                favoriteTemplateIdString = brainstormTemplate.id.uuidString
                Task {
                    try? await recordingManager.processTemplate(brainstormTemplate, for: recording)
                    coordinator.showRecordingDetail(recording)
                }
            }
            return
        }
        
        // Find the favorite template by UUID
        let descriptor = FetchDescriptor<Template>(
            predicate: #Predicate { template in
                template.id == favoriteId
            }
        )
        
        if let templates = try? modelContext.fetch(descriptor),
           let template = templates.first {
            Task {
                try? await recordingManager.processTemplate(template, for: recording)
                // Show the recording detail
                coordinator.showRecordingDetail(recording)
            }
        }
    }
    
    private func hintText(for state: RecordButton.RecordingState, isVoiceDetected: Bool = false) -> String {
        switch state {
        case .idle: return "Tap to record"
        case .recording: 
            return isVoiceDetected ? "Detecting voice..." : "Listening..."
        case .processing: return "Processing..."
        }
    }
    
    private func hintOpacity(for state: RecordButton.RecordingState) -> Double {
        switch state {
        case .idle: return 1.0
        case .recording: return 0.7
        case .processing: return 0.7
        }
    }
    
    private func microphoneIcon(for device: String) -> String {
        if device.contains("AirPods") || device.contains("Bluetooth") {
            return "airpodspro"
        } else if device.contains("Headset") || device.contains("Wired") {
            return "headphones"
        } else if device.contains("Car") {
            return "car.fill"
        } else if device.contains("USB") || device.contains("External") {
            return "mic.fill"
        } else {
            return "mic"
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .day], from: date, to: now)
        
        if let days = components.day, days > 0 {
            return days == 1 ? "Yesterday" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else {
            return "Just now"
        }
    }
    
    private func getFavoriteTemplateName() -> String? {
        guard let favoriteId = favoriteTemplateId else { return nil }
        let descriptor = FetchDescriptor<Template>(
            predicate: #Predicate { template in
                template.id == favoriteId
            }
        )
        let templates = try? modelContext.fetch(descriptor)
        return templates?.first?.name
    }
    
    private func templateIcon(for templateName: String) -> String {
        switch templateName.lowercased() {
        case let name where name.contains("summary"):
            return "doc.text"
        case let name where name.contains("action"):
            return "checklist"
        case let name where name.contains("brainstorm"):
            return "brain.head.profile"
        case let name where name.contains("quote"):
            return "quote.bubble"
        case let name where name.contains("outline"):
            return "list.bullet.indent"
        default:
            return "wand.and.stars"
        }
    }
    
    private func getDisplayText(for transcript: String, with aiTitle: String?) -> String {
        if let aiTitle = aiTitle,
           transcript.hasPrefix(aiTitle.replacingOccurrences(of: "...", with: "")) {
            // Skip the title portion and show continuation
            let titleWithoutEllipsis = aiTitle.replacingOccurrences(of: "...", with: "")
            return "..." + String(transcript.dropFirst(titleWithoutEllipsis.count)).trimmingCharacters(in: .whitespaces)
        } else {
            return transcript
        }
    }
    
}

// Template Chip Component
struct TemplateChip: View {
    let title: String
    let icon: String
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isDisabled ? Color.gray.opacity(0.2) : Color.blue.opacity(0.15))
            .foregroundColor(isDisabled ? .gray : .blue)
            .cornerRadius(16)
        }
        .disabled(isDisabled)
    }
}

#Preview {
    ContentView()
        .environment(AppCoordinator())
}