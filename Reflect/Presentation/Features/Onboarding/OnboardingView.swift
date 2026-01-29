import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State var currentPage = 0
    @Environment(\.modelContext) private var modelContext
    @State var viewModel: OnboardingViewModel?

    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "book.closed.fill",
            title: "Welcome to ReflectLearn",
            subtitle: "Capture your learning journey with voice, text, and images",
            color: .primaryDefault
        ),
        OnboardingPage(
            icon: "folder.fill.badge.gearshape",
            title: "Organize Your Learnings",
            subtitle: "Create categories, add hashtags, and find insights instantly",
            color: .success
        ),
        OnboardingPage(
            icon: "mic.fill",
            title: "Speak Your Thoughts",
            subtitle: "Record and transcribe in Indonesian or English",
            color: .warning
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }

                iCloudCheckPage
                    .tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            HStack(spacing: 8) {
                ForEach(0..<(pages.count + 1), id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.primaryDefault : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.bottom, Constants.Spacing.lg)

            navigationButtons
                .padding(.horizontal, Constants.Spacing.lg)
                .padding(.bottom, Constants.Spacing.xl)
        }
        .background(Color(.systemBackground))
        .onAppear {
            if viewModel == nil {
                viewModel = OnboardingViewModel(modelContext: modelContext)
            }
        }
        .task {
            await viewModel?.checkForCloudData()
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
