import SwiftUI
import SwiftData

struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var templateManager: TemplateManager?
    @State private var isEditMode = false

    let recording: Recording?
    let onTemplateSelected: (Template) -> Void
    
    var body: some View {
        NavigationStack {
            Group {
                if let manager = templateManager {
                    if manager.isLoading {
                        ProgressView("Loading templates...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if manager.orderedTemplates.isEmpty {
                        ContentUnavailableView(
                            "No Templates Available",
                            systemImage: "doc.text",
                            description: Text("Templates help transform your transcripts into structured notes")
                        )
                    } else {
                        List {
                            ForEach(manager.orderedTemplates, id: \.id) { template in
                                TemplateRow(
                                    template: template,
                                    isEditMode: isEditMode,
                                    action: {
                                        if !isEditMode {
                                            onTemplateSelected(template)
                                            dismiss()
                                        }
                                    }
                                )
                            }
                            .onMove(perform: isEditMode ? moveTemplates : nil)
                        }
                        .listStyle(.plain)
                        .environment(\.editMode, isEditMode ? .constant(.active) : .constant(.inactive))
                    }
                } else {
                    ProgressView("Loading templates...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isEditMode.toggle()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            if templateManager == nil {
                templateManager = TemplateManager(modelContext: modelContext)
            }
            await templateManager?.loadTemplates()
        }
    }
    
    private func moveTemplates(from source: IndexSet, to destination: Int) {
        templateManager?.reorderTemplates(from: source, to: destination)
    }
}

struct TemplateRow: View {
    let template: Template
    let isEditMode: Bool
    let action: () -> Void
    
    private var templateIcon: String {
        TemplateIcons.icon(for: template.name)
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // SF Symbol icon
                Image(systemName: templateIcon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                
                // Template info
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.system(.body, design: .default, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(template.templateDescription)
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Premium badge
                if template.isPremium {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.visible)
        .disabled(isEditMode)
    }
}

#Preview {
    TemplatePickerView(recording: nil) { template in
        // Template selected
    }
}