import SwiftUI

struct HashtagEditor: View {
    @Binding var hashtags: [String]
    var suggestions: [String]
    var maxHashtags: Int

    @State private var newHashtag = ""
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    init(
        hashtags: Binding<[String]>,
        suggestions: [String] = [],
        maxHashtags: Int = Constants.Limits.maxHashtagsPerReflection
    ) {
        self._hashtags = hashtags
        self.suggestions = suggestions
        self.maxHashtags = maxHashtags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            // Current hashtags
            FlowLayout(spacing: Constants.Spacing.xs) {
                ForEach(hashtags, id: \.self) { hashtag in
                    HashtagChip(
                        text: hashtag,
                        isRemovable: true,
                        onRemove: {
                            removeHashtag(hashtag)
                        }
                    )
                }

                // Add button
                if hashtags.count < maxHashtags {
                    addButton
                }
            }

            // Input field (when focused)
            if isFocused {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    HStack {
                        Text("#")
                            .foregroundColor(.secondary)

                        TextField("Add hashtag", text: $newHashtag)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                            .onSubmit {
                                addHashtag()
                            }

                        if !newHashtag.isEmpty {
                            Button("Add") {
                                addHashtag()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primaryDefault)
                        }
                    }
                    .padding(Constants.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                            .stroke(Color.primaryDefault, lineWidth: 1)
                    )

                    // Suggestions
                    if !filteredSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Constants.Spacing.xs) {
                                ForEach(filteredSuggestions, id: \.self) { suggestion in
                                    Button(action: {
                                        addHashtag(suggestion)
                                    }) {
                                        Text("#\(suggestion)")
                                            .font(.caption)
                                            .foregroundColor(.primaryDefault)
                                            .padding(.horizontal, Constants.Spacing.xs)
                                            .padding(.vertical, Constants.Spacing.xxs)
                                            .background(
                                                Capsule()
                                                    .fill(Color.primaryDefault.opacity(0.1))
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var addButton: some View {
        Button(action: {
            isFocused = true
        }) {
            HStack(spacing: Constants.Spacing.xxs) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.subheadline)
            .foregroundColor(.primaryDefault)
            .padding(.horizontal, Constants.Spacing.sm)
            .padding(.vertical, Constants.Spacing.xs)
            .background(
                Capsule()
                    .strokeBorder(Color.primaryDefault, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
    }

    private var filteredSuggestions: [String] {
        guard !newHashtag.isEmpty else {
            return suggestions.filter { !hashtags.contains($0) }.prefix(5).map { $0 }
        }

        return suggestions
            .filter { $0.lowercased().contains(newHashtag.lowercased()) && !hashtags.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    private func addHashtag(_ tag: String? = nil) {
        let tagToAdd = (tag ?? newHashtag)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")

        guard !tagToAdd.isEmpty,
              !hashtags.contains(tagToAdd),
              hashtags.count < maxHashtags,
              tagToAdd.count <= Constants.Limits.hashtagMaxLength else {
            return
        }

        withAnimation {
            hashtags.append(tagToAdd)
        }

        newHashtag = ""
        HapticManager.shared.lightImpact()
    }

    private func removeHashtag(_ hashtag: String) {
        withAnimation {
            hashtags.removeAll { $0 == hashtag }
        }
        HapticManager.shared.lightImpact()
    }
}

#Preview {
    @Previewable @State var hashtags = ["swift", "ios", "learning"]

    HashtagEditor(
        hashtags: $hashtags,
        suggestions: ["programming", "swiftui", "xcode", "development"]
    )
    .padding()
}
