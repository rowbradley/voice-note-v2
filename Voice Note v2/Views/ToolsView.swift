//
//  ToolsView.swift
//  Voice Note v2
//
//  Tools tab with templates and settings.
//  Templates will be user-configurable (bookmarked for future implementation).
//

import SwiftUI
import SwiftData

struct ToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(templates) { template in
                        NavigationLink(destination: TemplateDetailView(template: template)) {
                            TemplateRowView(template: template)
                        }
                    }
                } header: {
                    Text("Templates")
                } footer: {
                    Text("Templates transform your transcriptions into structured formats.")
                }

                Section("App") {
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct TemplateRowView: View {
    let template: Template

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: TemplateIcons.icon(for: template.name))
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(.body, design: .rounded, weight: .medium))

                if !template.templateDescription.isEmpty {
                    Text(template.templateDescription)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Placeholder for template detail/editing view
struct TemplateDetailView: View {
    let template: Template

    var body: some View {
        List {
            Section("Name") {
                Text(template.name)
            }

            Section("Description") {
                Text(template.templateDescription.isEmpty ? "No description" : template.templateDescription)
                    .foregroundColor(template.templateDescription.isEmpty ? .secondary : .primary)
            }

            Section("Prompt") {
                Text(template.prompt)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ToolsView()
}
