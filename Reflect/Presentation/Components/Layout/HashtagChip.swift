import SwiftUI

struct HashtagChip: View {
    let text: String
    var isSelected: Bool
    var isRemovable: Bool
    var showRemove: Bool
    var showHashSymbol: Bool
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    init(
        text: String,
        isSelected: Bool = false,
        isRemovable: Bool = false,
        showRemove: Bool = false,
        showHashSymbol: Bool = true,
        onTap: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.text = text
        self.isSelected = isSelected
        self.isRemovable = isRemovable || showRemove
        self.showRemove = showRemove
        self.showHashSymbol = showHashSymbol
        self.onTap = onTap
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: Constants.Spacing.xxs) {
            Text(showHashSymbol ? "#\(text)" : text)
                .font(.subheadline)
                .foregroundColor(isSelected ? .white : .primaryDefault)

            if isRemovable {
                Button(action: {
                    HapticManager.shared.lightImpact()
                    onRemove?()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .primaryDefault.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, Constants.Spacing.sm)
        .padding(.vertical, Constants.Spacing.xs)
        .background(
            Capsule()
                .fill(isSelected ? Color.primaryDefault : Color.primaryDefault.opacity(0.15))
        )
        .contentShape(Capsule())
        .onTapGesture {
            HapticManager.shared.lightImpact()
            onTap?()
        }
    }
}

// MARK: - Hashtag Chips Row

struct HashtagChipsRow: View {
    let hashtags: [Hashtag]
    var selectedHashtags: Set<String>
    var onHashtagTap: (String) -> Void

    init(
        hashtags: [Hashtag],
        selectedHashtags: Set<String> = [],
        onHashtagTap: @escaping (String) -> Void
    ) {
        self.hashtags = hashtags
        self.selectedHashtags = selectedHashtags
        self.onHashtagTap = onHashtagTap
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.Spacing.xs) {
                // "All" chip
                HashtagChip(
                    text: "All",
                    isSelected: selectedHashtags.isEmpty
                ) {
                    onHashtagTap("")
                }

                // Hashtag chips
                ForEach(hashtags) { hashtag in
                    HashtagChip(
                        text: hashtag.name,
                        isSelected: selectedHashtags.contains(hashtag.name)
                    ) {
                        onHashtagTap(hashtag.name)
                    }
                }
            }
            .padding(.horizontal, Constants.Spacing.md)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            HashtagChip(text: "swift")
            HashtagChip(text: "ios", isSelected: true)
            HashtagChip(text: "learning", isRemovable: true)
        }
    }
    .padding()
}
