import AVFoundation
import Testing
@testable import Reflect

struct PermissionPrimerTests {
    // MARK: - AVAuthorizationStatus mapping

    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, PermissionState.notDetermined),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .denied)
    ])
    func mapsAuthorizationStatus(status: AVAuthorizationStatus, expected: PermissionState) {
        #expect(PermissionState(status) == expected)
    }

    // MARK: - Single permission

    @Test func notDeterminedShowsPrimer() {
        #expect(PermissionPrimer.nextStep(for: [.notDetermined]) == .primer)
    }

    @Test func grantedProceeds() {
        #expect(PermissionPrimer.nextStep(for: [.granted]) == .proceed)
    }

    @Test func deniedShowsSettings() {
        #expect(PermissionPrimer.nextStep(for: [.denied]) == .settings)
    }

    @Test(arguments: [AVAuthorizationStatus.denied, .restricted])
    func deniedOrRestrictedCameraShowsSettings(status: AVAuthorizationStatus) {
        #expect(PermissionPrimer.nextStep(for: [PermissionState(status)]) == .settings)
    }

    // MARK: - Several permissions (voice asks for mic + speech)

    @Test func grantedAndNotDeterminedShowsPrimer() {
        #expect(PermissionPrimer.nextStep(for: [.granted, .notDetermined]) == .primer)
    }

    @Test func notDeterminedAndDeniedShowsSettings() {
        #expect(PermissionPrimer.nextStep(for: [.notDetermined, .denied]) == .settings)
    }

    @Test func allGrantedProceeds() {
        #expect(PermissionPrimer.nextStep(for: [.granted, .granted]) == .proceed)
    }

    @Test func noPermissionsProceeds() {
        #expect(PermissionPrimer.nextStep(for: []) == .proceed)
    }
}
