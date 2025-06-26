# Claude Development Guidelines

High-value, generalizable iOS development patterns and principles for any app project.

## Core Development Philosophy

**Modular • Efficient • Tweakable • Clean Code**

- Write code that can be easily understood and modified
- Prefer composition over inheritance
- Keep components focused and single-purpose
- Make performance implications explicit

## iOS Configuration Patterns

### Simple Plist Configuration (Recommended for non-secrets)
```swift
// Config.plist
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>backend_url</key>
    <string>https://api.example.com</string>
</dict>
</plist>

// Config.swift
enum Config {
    private static let plist: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        return plist
    }()
    
    static let backendURL = plist["backend_url"] as? String ?? ""
}
```

**Why**: Dead simple, easy to debug, no build complexity.

### Bootstrap Token Authentication (Recommended for API secrets)
```swift
struct BootstrapTokenManager {
    func getToken() async throws -> String {
        if let cached = getCachedValidToken() { return cached }
        
        let request = BootstrapRequest(
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            platform: "iOS"
        )
        
        let response = try await api.post("/auth/bootstrap", body: request)
        cacheToken(response.token, expiresIn: response.expiresIn)
        return response.token
    }
}
```

**Why**: No secrets in binary, per-device tokens, revocable, simple implementation.

## SwiftData Best Practices

### Always Specify Store URL
```swift
// ❌ BAD - Uses undocumented default location
let container = try ModelContainer(for: schema)

// ✅ GOOD - Explicit, predictable location
let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                       in: .userDomainMask)[0]
    .appendingPathComponent("YourApp.store")

let config = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true)
let container = try ModelContainer(for: schema, configurations: [config])
```

### Proper Store Deletion
```swift
func deleteStore() throws {
    // Delete all SQLite files including WAL and SHM
    for ext in ["", "-wal", "-shm"] {
        let fileURL = ext.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + ext)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

### Schema Compatibility Check
```swift
// Before creating container, check if existing store is compatible
if FileManager.default.fileExists(atPath: storeURL.path) {
    do {
        let testConfig = ModelConfiguration(schema: schema, url: storeURL, allowsSave: false)
        _ = try ModelContainer(for: schema, configurations: [testConfig])
    } catch {
        try deleteStore() // Store is incompatible
    }
}
```

## Voice/Audio App Patterns

### Reliable Audio Recording
```swift
class AudioRecordingService {
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])
        
        // Handle interruptions
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: session
        )
    }
    
    private func setupRecorder(url: URL) throws -> AVAudioRecorder {
        // Query device capabilities, don't hardcode
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        return try AVAudioRecorder(url: url, settings: settings)
    }
}
```

### Hybrid Transcription Pattern
```swift
protocol TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String
}

class HybridTranscriptionService: TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String {
        // Try on-device first for privacy and speed
        do {
            return try await onDeviceService.transcribe(audioURL: audioURL)
        } catch {
            // Fallback to cloud service
            return try await cloudService.transcribe(audioURL: audioURL)
        }
    }
}
```

## Architecture Principles

### Clean Architecture
- **Models**: Pure data structures, no business logic
- **Services**: Single-purpose, protocol-based
- **ViewModels**: UI state management only
- **Views**: Declarative UI, minimal logic

### Protocol-Oriented Design
```swift
protocol AudioService {
    func startRecording() async throws
    func stopRecording() async throws -> URL
}

protocol TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String
}
```

### Dependency Injection
```swift
class RecordingManager {
    private let audioService: AudioService
    private let transcriptionService: TranscriptionService
    
    init(audioService: AudioService, transcriptionService: TranscriptionService) {
        self.audioService = audioService
        self.transcriptionService = transcriptionService
    }
}
```

## AI Template Prompt Management

### Prompt Storage Architecture

**Primary Location**: `Models/Template.swift`
```swift
static let builtInTemplates: [TemplateJSON] = [
    TemplateJSON(
        id: "cleanup",                    // Unique identifier
        name: "Cleanup",                  // Display name in UI
        description: "Remove fillers...", // Short description
        prompt: "Clean up this transcript...", // ⭐ THE ACTUAL AI PROMPT
        category: TemplateCategory.productivity.rawValue,
        isPremium: false,
        sortOrder: 1,
        version: 2                        // Version for auto-updates
    )
]
```

### Data Flow: Swift File → Database → AI
```
Template.swift → TemplateManager → SwiftData Database → CloudAIService → Backend → OpenAI
     ↑                ↑                    ↑                   ↑
   Source of        Handles           Local Cache         Sends prompt
    Truth          Updates                                + transcript
```

### Automatic Update System

**How It Works**:
1. **Version Checking**: `TemplateManager.updateBuiltInTemplatesIfNeeded()` runs on every app launch
2. **Name Matching**: Finds existing templates by name (reliable across app updates)
3. **Version Comparison**: Updates database when Swift file version > database version
4. **Automatic Sync**: No manual database work required

**Update Process**:
```swift
// 1. Edit prompt in Template.swift
prompt: "Transform the following transcript into...",

// 2. Increment version number
version: 3  // Was 2, now 3

// 3. Build app - updates happen automatically
```

### How to Update Prompts

#### ✅ **Correct Process**:
1. **Edit `Models/Template.swift`**
2. **Find your template** in the `builtInTemplates` array
3. **Update the `prompt` string** with new instructions
4. **Increment the `version` number** (e.g., `2` → `3`)
5. **Build the app** - database updates automatically

#### ❌ **Don't Do This**:
- ❌ Edit database directly
- ❌ Forget to increment version number
- ❌ Change template names (breaks matching)
- ❌ Edit backend API code (prompts come from iOS app)

### Template Prompt Best Practices

#### **Structure Your Prompts**:
```swift
prompt: """
[CLEAR INSTRUCTION]. Do not include a header that repeats the template name. 
Begin directly with [EXPECTED OUTPUT TYPE]. Use sentence case headers.

[SPECIFIC GUIDELINES]:
1. [Detailed instruction 1]
2. [Detailed instruction 2]
3. [Detailed instruction 3]

[OUTPUT FORMAT]:
- [Format specification]
- [Additional requirements]

Output as [FORMAT TYPE] with [STRUCTURE REQUIREMENTS].
"""
```

#### **Prevent ALL CAPS Headers**:
- ✅ "Do not include a header that repeats the template name"
- ✅ "Begin directly with the main content"
- ✅ "Use sentence case headers" 
- ✅ "Use normal sentence case for any headers (e.g., 'Quote 1' not 'QUOTE 1')"

#### **Clear Output Instructions**:
- ✅ "Begin directly with..." (eliminates redundant headers)
- ✅ "Output as [specific format]" (sets expectations)
- ✅ "Use sentence case..." (prevents ALL CAPS)

### Current Template Status

**All Templates (Version 2+)**:
- ✅ **Cleanup**: Remove fillers, fix grammar
- ✅ **Smart Summary**: One-sentence + adaptive summary  
- ✅ **Action List**: Extract actionable tasks
- ✅ **Message Ready**: Transform to polished text reply (v3)
- ✅ **Idea Outline**: Hierarchical outline structure
- ✅ **Brainstorm**: Extract and cluster ideas
- ✅ **Key Quotes**: Impactful and shareable quotes
- ✅ **Next Questions**: Follow-up questions
- ✅ **Flashcard Maker**: Study flashcards
- ✅ **Tone Analysis**: Emotional journey analysis

### Debugging Template Updates

**Console Logs to Watch For**:
```
✅ "Checking for built-in template updates..."
✅ "Updating built-in template: [Name] v1 → v2"  
✅ "Updated 3 built-in templates"
❌ "All built-in templates are up to date" (if expecting updates)
```

**Troubleshooting**:
- **No updates happening**: Check version numbers incremented
- **Template not found**: Verify template name matches exactly
- **Wrong prompt used**: Old database entries - check version numbers

### Making Bulk Updates

**Process for Multiple Template Changes**:
```swift
// 1. Update all desired templates in Template.swift
// 2. Increment ALL changed template versions
// 3. Build once - all updates apply automatically
// 4. Check console for "Updated X built-in templates"
```

**Version Strategy**:
- **Major prompt rewrites**: Increment by 1 (v2 → v3)
- **Minor tweaks**: Still increment by 1 (ensures update)
- **Testing changes**: Use unique version numbers to force updates

### Template Icon Management

**Icon Mapping**: `Views/TemplatePickerView.swift`
```swift
struct TemplateIconMapping {
    static func icon(for templateName: String) -> String {
        switch templateName {
        case "Cleanup": return "wand.and.stars"
        case "Tone Analysis": return "heart.text.square"  // ← Nice icon!
        case "Key Quotes": return "quote.opening"
        default: return "doc.text"
        }
    }
}
```

**To Change Icons**: Edit the mapping, no version increment needed.

## Development Guidelines

### Error Handling
- Always provide fallback options for critical functionality
- Handle errors gracefully with user-friendly messages
- Use async/await to prevent UI blocking

### Logging
```swift
import os.log

private let logger = Logger(subsystem: "com.yourapp", category: "ComponentName")

// Use throughout code instead of print()
logger.info("Operation completed successfully")
logger.error("Operation failed: \(error)")
```

### Performance
- Use lazy loading for expensive operations
- Cache results when appropriate
- Profile memory usage with large data sets
- Optimize timer frequencies for battery life

## Swift 6 Concurrency Best Practices

### Task Management Pattern
```swift
class ServiceClass {
    private var backgroundTasks: Set<Task<Void, Never>> = []
    
    func startOperation() {
        // Store task references for proper cleanup
        let task = Task {
            // Long-running operation
        }
        backgroundTasks.insert(task)
        
        // Auto-cleanup on completion
        task.result.get() // Handle result
        backgroundTasks.remove(task)
    }
    
    deinit {
        // Cancel all background tasks
        backgroundTasks.forEach { $0.cancel() }
    }
}
```

### Variable Scope in Async Functions
```swift
// ❌ BAD - Variable declared inside do block
func processData() async {
    do {
        let progressTask = Task { /* progress updates */ }
        // ... main work
    } catch {
        progressTask.cancel() // ❌ Out of scope
    }
}

// ✅ GOOD - Variable declared at function level
func processData() async {
    var progressTask: Task<Void, Never>?
    defer { progressTask?.cancel() } // Automatic cleanup
    
    do {
        progressTask = Task { /* progress updates */ }
        // ... main work
    } catch {
        // progressTask is accessible here
    }
}
```

### Actor Isolation
```swift
@MainActor
class UIService {
    private let logger = Logger(subsystem: "app", category: "UIService")
    
    func updateUI() {
        // In closures, use explicit self for actor-isolated properties
        Task {
            self.logger.info("Updating UI") // ✅ Explicit self required
        }
    }
    
    deinit {
        // ❌ Don't call @MainActor methods in deinit
        // stopUpdates() // Would cause compilation error
        
        // ✅ Only non-isolated cleanup
        timer?.invalidate()
    }
}
```

## What to Avoid

### XCConfig Files
- Too complex for simple secrets management
- Build system complications
- Debugging difficulties
- Use plist files or bootstrap tokens instead

### Hardcoded Values
- Audio settings (query device capabilities)
- URLs and endpoints (use configuration)
- Timeouts and limits (make configurable)

### Swift 6 Concurrency Anti-Patterns
- Calling @MainActor methods from deinit
- Variable scope issues in async functions
- Missing explicit `self` in closures
- String concatenation in Logger calls (use interpolation)
- Infinite animations without cancellation

### iOS Battery Drain Anti-Pattern
❌ **Don't**: Unthrottled Combine publishers + high-frequency timers (10Hz+)  
✅ **Do**: `.throttle(for: .milliseconds(200), latest: true)` + reduce timer frequencies  
**Common trap**: Audio monitoring timers causing phone heating  
**Quick fix**: Throttle UI updates, optimize timer frequencies to 5Hz or lower

### Synchronous Operations
- File I/O on main thread
- Network requests without async/await
- Heavy processing in UI code

## Testing Strategy

- Unit tests for business logic
- Integration tests for data flow
- UI tests for critical user paths
- Mock external dependencies
- Test error scenarios thoroughly

## Xcode Project Management Guidelines

When providing file modification instructions for Xcode projects, always include full folder paths for clarity:

### File Location Format
```
❌ BAD: "Remove FlexibleMarkdownView.swift from the project"
✅ GOOD: "Remove Views/Components/FlexibleMarkdownView.swift from the project"

❌ BAD: "Add EnhancedMarkdownView.swift to Xcode"  
✅ GOOD: "Add Views/Components/EnhancedMarkdownView.swift to Xcode project"
```

### Swift Package Dependencies
When adding packages:
1. **Always specify exact repository URL**
2. **Include version requirements** (e.g., "Up to Next Major Version" with minimum)
3. **Specify target name** for package addition
4. **Provide fallback instructions** if package addition fails

### File Management Best Practices
- **Create `.legacy` backups** before removing files from Xcode
- **Use compatibility placeholders** to maintain build during transitions
- **Always verify folder structure** before giving file paths
- **Include both relative and absolute paths** when helpful for clarity

### Build Verification
- **Test build after each major change**
- **Document expected warnings** vs actual errors
- **Provide rollback instructions** if builds fail