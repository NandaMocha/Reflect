import SwiftUI

struct StreakCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let isActive: Bool
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    flameIcon
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(currentStreak)-Day Streak")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Longest: \(longestStreak) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: currentStreak > 0
                                ? [activeStreakColor.opacity(0.6), activeStreakColor.opacity(0.2)]
                                : [.gray.opacity(0.3), .gray.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: currentStreak > 0 ? 3 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var flameIcon: some View {
        ZStack {
            if currentStreak > 0 {
                // Multi-colored fire effect
                ZStack {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange, .yellow],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .opacity(0.8)
                }
            } else {
                Image(systemName: "flame")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
    }

    private var flameColor: Color {
        if currentStreak >= 30 {
            return .purple
        } else if currentStreak >= 14 {
            return .orange
        } else if currentStreak >= 7 {
            return .yellow
        } else if currentStreak >= 3 {
            return .red
        } else {
            return .gray
        }
    }

    private var activeStreakColor: Color {
        isActive ? flameColor : .gray
    }
}
