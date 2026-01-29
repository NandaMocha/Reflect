import SwiftUI

struct ReflectionCard: View {
    let reflection: Reflection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                    Text(reflection.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(reflection.contentPreview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer(minLength: 8)
                    
                    HStack(spacing: Constants.Spacing.xs) {
                        // Media indicators
                        if reflection.hasImages || reflection.hasVoiceRecordings {
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
                        }

                        // Date
                        Text(reflection.createdAt.shortFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: Constants.Spacing.xs) {
                    if let thumbnail = reflection.firstImage?.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
                    }
                    
                    if reflection.images.count > 1 {
                        Text("+ \(reflection.images.count - 1)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: 50, alignment: .center)
                    }

                }
            }
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
