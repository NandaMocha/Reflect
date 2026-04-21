import Foundation

struct BadgeUnlockEvent {
    let badge: Badge
    let isNewUnlock: Bool
    let unlockedCount: Int
    let celebrationTrigger: CelebrationTrigger

    enum CelebrationTrigger {
        case confetti
        case sparkles
        case fireworks
        case maximum
        case none
    }
}
