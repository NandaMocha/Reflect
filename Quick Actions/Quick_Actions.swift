//
//  Quick_Actions.swift
//  Quick Actions
//
//  Reflect Widget - Quick access to create reflections
//

import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> ()) {
        let entry = QuickActionsEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        // Update every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let entry = QuickActionsEntry(date: currentDate)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget View

struct QuickActionsWidgetView: View {
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        smallWidgetView
    }

    private var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // App logo (30x30, top-left). Uses a dedicated "AppLogo" imageset because
            // the `AppIcon` asset name is reserved and can't be loaded via Image(_:)
            // at runtime.
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))

            VStack(spacing: 16) {
                // Top section - Write button
                writeButton

                // Bottom section - Camera and Voice buttons
                HStack(spacing: 20) {
                    cameraButton
                    voiceButton
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                // Clean white background
                Color(hex: "FEFEFE")

                // Subtle gradient overlay for depth
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.black.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
    }

    // MARK: - Action Buttons (Small)

    private var writeButton: some View {
        Link(destination: URL(string: "reflect://write")!) {
            HStack(spacing: 8) {
                ZStack {
                    // Soft glow effect
                    Circle()
                        .fill(Color(hex: "628141").opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "pencil")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "628141"), Color(hex: "40513B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Write")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "40513B"), Color(hex: "628141")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.trailing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                ZStack {
                    // Glass capsule effect
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)

                    // Subtle inner glow
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.8),
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .padding(0.5)
                }
            )
        }
    }

    private var cameraButton: some View {
        Link(destination: URL(string: "reflect://camera")!) {
            ZStack {
                // Soft shadow/glow
                Circle()
                    .fill(Color(hex: "E67E22").opacity(0.12))
                    .frame(width: 60, height: 60)

                // Glass circle
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)

                // Subtle highlight
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 44, height: 22)

                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "E67E22"), Color(hex: "D35400")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 52, height: 52)
        }
    }

    private var voiceButton: some View {
        Link(destination: URL(string: "reflect://voice")!) {
            ZStack {
                // Soft shadow/glow
                Circle()
                    .fill(Color(hex: "9B59B6").opacity(0.12))
                    .frame(width: 60, height: 60)

                // Glass circle
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)

                // Subtle highlight
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 44, height: 22)

                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "9B59B6"), Color(hex: "8E44AD")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 52, height: 52)
        }
    }
}

// MARK: - Widget Configuration

struct Quick_Actions: Widget {
    let kind: String = "Quick_Actions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            if #available(iOS 17.0, *) {
                QuickActionsWidgetView()
                    .containerBackground(.clear, for: .widget)
            } else {
                QuickActionsWidgetView()
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Reflect")
        .description("Quick access to write, capture photos, or record voice reflections.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Color Extension for Widget

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    Quick_Actions()
} timeline: {
    QuickActionsEntry(date: .now)
}
