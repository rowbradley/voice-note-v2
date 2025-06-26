import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingResetConfirmation = false
    @State private var isResetting = false
    
    // User preferences
    @AppStorage("autoDeleteOldRecordings") private var autoDeleteOldRecordings = false
    @AppStorage("deleteRecordingsAfterDays") private var deleteRecordingsAfterDays = 30
    @AppStorage("defaultTemplateId") private var defaultTemplateId: String = ""
    @AppStorage("recordingQuality") private var recordingQuality = "high"
    @AppStorage("autoApplyDefaultTemplate") private var autoApplyDefaultTemplate = false
    @AppStorage("autoGenerateTitles") private var autoGenerateTitles = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    Picker("Audio Quality", selection: $recordingQuality) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    
                    Toggle("Background Recording", isOn: .constant(true))
                        .disabled(true)
                }
                
                Section("Transcription") {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text("English (US)")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Auto-transcribe", isOn: .constant(true))
                        .disabled(true)
                }
                
                Section("Recording Settings") {
                    Toggle("Auto-generate Titles", isOn: $autoGenerateTitles)
                    
                    if autoGenerateTitles {
                        Text("Uses first sentence of transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Generate Summaries", isOn: .constant(true))
                        .disabled(true)
                }
                
                Section("Templates") {
                    NavigationLink(destination: DefaultTemplatePickerView(selectedTemplateId: $defaultTemplateId)) {
                        HStack {
                            Text("Default Template")
                            Spacer()
                            Text(defaultTemplateId.isEmpty ? "None" : "Selected")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle("Auto-apply Default Template", isOn: $autoApplyDefaultTemplate)
                        .disabled(defaultTemplateId.isEmpty)
                }
                
                Section("Storage") {
                    HStack {
                        Text("Used Space")
                        Spacer()
                        Text("0 MB")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Auto-delete Old Recordings", isOn: $autoDeleteOldRecordings)
                    
                    if autoDeleteOldRecordings {
                        Stepper("Delete after \(deleteRecordingsAfterDays) days", 
                               value: $deleteRecordingsAfterDays, 
                               in: 7...90, 
                               step: 7)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clear Cache") {
                        // Cache clearing not implemented yet
                    }
                    .foregroundColor(.red)
                    .disabled(true)
                }
                
                Section("Data Management") {
                    Button(action: {
                        showingResetConfirmation = true
                    }) {
                        HStack {
                            if isResetting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Resetting...")
                            } else {
                                Image(systemName: "trash")
                                Text("Clear Local Data")
                            }
                        }
                        .foregroundColor(.red)
                    }
                    .disabled(isResetting)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Clear All Data?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Data", role: .destructive) {
                    Task {
                        await resetDatabase()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will delete all recordings, transcripts, and notes. This action cannot be undone.")
            }
        }
    }
    
    private func resetDatabase() async {
        isResetting = true
        
        // For now, just inform the user they need to restart
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        await MainActor.run {
            isResetting = false
            dismiss()
            // In a real implementation, we'd trigger the app-level reset
            // For now, the user will need to force-quit and restart
        }
    }
}

// Default Template Picker View
struct DefaultTemplatePickerView: View {
    @Binding var selectedTemplateId: String
    @Environment(\.dismiss) private var dismiss
    @State private var templateManager = TemplateManager()
    
    var body: some View {
        List {
            // None option
            Button(action: {
                selectedTemplateId = ""
                dismiss()
            }) {
                HStack {
                    Text("None")
                    Spacer()
                    if selectedTemplateId.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
            }
            .foregroundColor(.primary)
            
            // Templates by category
            ForEach(templateManager.groupedTemplates, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.templates) { template in
                        Button(action: {
                            selectedTemplateId = template.id.uuidString
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.system(.body, design: .rounded))
                                    Text(template.templateDescription)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                if selectedTemplateId == template.id.uuidString {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationTitle("Default Template")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await templateManager.loadTemplates()
        }
    }
}

#Preview {
    SettingsView()
}