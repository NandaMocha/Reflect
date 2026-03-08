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
                    .stroke(activeStreakColor.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var flameIcon: some View {
        ZStack {
            if currentStreak > 0 {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundColor(flameColor)
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
