import SwiftUI

struct HowToAchieveCard: View {
    let requirementDescription: String

    init(requirementDescription: String) {
        self.requirementDescription = requirementDescription
    }

    init(badge: Badge) {
        if let badgeID = BadgeID(rawValue: badge.id) {
            self.requirementDescription = badgeID.requirementDescription
        } else {
            self.requirementDescription = badge.badgeDescription
        }
    }

    init(badgeID: BadgeID) {
        self.requirementDescription = badgeID.requirementDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)

                Text("How to Achieve")
                    .font(.headline)
            }

            Text(requirementDescription)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HowToAchieveCard(badgeID: .fiveReflections)
        .padding()
}
