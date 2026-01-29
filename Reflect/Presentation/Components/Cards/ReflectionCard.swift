import SwiftUI

struct ReflectionCard: View {
    let reflection: Reflection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                let imageSize = geometry.size.width * 0.35 // 35% of card width

                ZStack(alignment: .topTrailing) {
                    // Main content
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text(reflection.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(reflection.contentPreview)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)

                        // Indicators row
                        HStack(spacing: Constants.Spacing.xs) {
                            // Hashtags
                            if !reflection.hashtags.isEmpty {
                                ForEach(reflection.hashtags.prefix(2)) { hashtag in
                                    Text(hashtag.displayName)
                                        .font(.caption)
                                        .foregroundColor(.primaryDefault)
                                }

                                if reflection.hashtags.count > 2 {
                                    Text("+\(reflection.hashtags.count - 2)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            // Media indicators
                            HStack(spacing: Constants.Spacing.xxs) {
                                if reflection.hasImages {
                                    Image(systemName: "photo")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if reflection.hasVoiceRecordings {
                                    Image(systemName: "mic")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Date
                            Text(reflection.createdAt.shortFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(Constants.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    // Image in top-right corner
                    if let thumbnail = reflection.firstImage?.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: imageSize, height: imageSize)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
                            .padding(Constants.Spacing.sm)
                    }
                }
            }
            .frame(height: 100) // Compact height
            .glassCard()
        }
    }
}

// MARK: - Compact Variant

struct ReflectionCardCompact: View {
    let reflection: Reflection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(reflection.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(reflection.contentPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    Text(reflection.createdAt.shortFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()


                }
            }
            .padding(Constants.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PressableCardStyle())
    }
}

#Preview {
    let reflection = Reflection(
        title: "Today's Learning Reflection",
        plainTextContent: "I learned a lot about SwiftUI today. The declarative syntax is really intuitive and makes building UIs much faster."
    )

    VStack(spacing: 16) {
        ReflectionCard(reflection: reflection) {
            print("Tapped")
        }

        ReflectionCardCompact(reflection: reflection) {
            print("Tapped")
        }
    }
    .padding()
}
