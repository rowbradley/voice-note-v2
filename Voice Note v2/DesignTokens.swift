//
//  DesignTokens.swift
//  Voice Note v2
//
//  Single source of truth for all spacing, sizing, and styling values.
//  Enables precise communication: "use .sm (8pt)" instead of "a little smaller"
//

import SwiftUI

// MARK: - Design Tokens

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

// MARK: - Shared Components

/// Template Chip Component for quick template selection
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

// MARK: - Template Icons

/// Centralized template icon mapping
enum TemplateIcons {
    /// Returns the appropriate SF Symbol for a template name
    static func icon(for templateName: String) -> String {
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
        case let name where name.contains("flashcard"):
            return "rectangle.stack"
        case let name where name.contains("mood"):
            return "heart"
        case let name where name.contains("reply"):
            return "bubble.left.and.bubble.right"
        case let name where name.contains("section"):
            return "text.alignleft"
        case let name where name.contains("question"):
            return "questionmark.circle"
        default:
            return "wand.and.stars"
        }
    }
}

// MARK: - Formatters

/// Centralized formatting utilities
enum Formatters {
    /// Formats a duration in seconds to "M:SS" format
    /// Handles NaN/infinite values safely
    static func duration(_ duration: TimeInterval) -> String {
        let safeDuration = duration.isFinite ? max(0, duration) : 0.0
        let minutes = Int(safeDuration) / 60
        let seconds = Int(safeDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formats a date relative to now (e.g., "Just now", "2h ago", "Yesterday")
    static func relativeDate(_ date: Date) -> String {
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

    /// Formats date with medium date and short time (e.g., "Jan 16, 2026 at 2:30 PM")
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Formats date as time only (e.g., "2:30 PM")
    static func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
