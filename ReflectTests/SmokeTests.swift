import Testing
@testable import Reflect

struct SmokeTests {
    @Test func appModuleIsReachable() {
        let action = WidgetAction.insight
        #expect(action == .insight)
    }
}
