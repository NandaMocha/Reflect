import SwiftUI

// MARK: - Celebration View Modifier

extension View {
    /// Shows a celebration overlay when the binding becomes true
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - badge: The badge that was unlocked (optional)
    ///   - trigger: The celebration trigger type
    func celebration(
        isPresented: Binding<Bool>,
        badge: Badge?,
        trigger: BadgeUnlockEvent.CelebrationTrigger
    ) -> some View {
        self.overlay(
            Group {
                if isPresented.wrappedValue {
                    CelebrationView(
                        trigger: trigger,
                        badgeName: badge?.name ?? "Achievement Unlocked!",
                        onDismiss: {
                            isPresented.wrappedValue = false
                        }
                    )
                    .transition(.opacity)
                }
            },
            alignment: .center
        )
        .animation(.easeInOut, value: isPresented.wrappedValue)
    }

    /// Shows a celebration overlay for a specific badge ID
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - badgeID: The badge ID that was unlocked
    func celebration(
        isPresented: Binding<Bool>,
        badgeID: BadgeID
    ) -> some View {
        celebration(
            isPresented: isPresented,
            badge: nil,
            trigger: badgeID.celebration
        )
    }

    /// Shows a celebration overlay with just the trigger type
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - trigger: The celebration trigger type
    func celebration(
        isPresented: Binding<Bool>,
        trigger: BadgeUnlockEvent.CelebrationTrigger
    ) -> some View {
        celebration(
            isPresented: isPresented,
            badge: nil,
            trigger: trigger
        )
    }
}

// MARK: - Usage Example

/*
 In your view:

 struct MyView: View {
     @State private var showCelebration = false
     @State private var unlockedBadge: Badge?

     var body: some View {
         VStack {
             Button("Unlock Badge") {
                 // Trigger badge unlock
                 unlockedBadge = myBadge
                 showCelebration = true
             }
         }
         .celebration(
             isPresented: $showCelebration,
             badge: unlockedBadge,
             trigger: .confetti
         )
     }
 }

 // Or with badge ID:
 .celebration(
     isPresented: $showCelebration,
     badgeID: .threeDayStreak
 )
 }
*/
