import AppKit
import XCTest

@testable import PowerTools

@MainActor
final class ApplicationActivationControllerTests: XCTestCase {
    func testWindowlessIdleAppUsesAccessoryPolicy() {
        XCTAssertEqual(
            ApplicationActivationController.activationPolicy(
                hasUserFacingWindows: false,
                isAwaitingWindowPresentation: false
            ),
            .accessory
        )
    }

    func testVisibleOrPendingUserWindowUsesRegularPolicy() {
        XCTAssertEqual(
            ApplicationActivationController.activationPolicy(
                hasUserFacingWindows: true,
                isAwaitingWindowPresentation: false
            ),
            .regular
        )
        XCTAssertEqual(
            ApplicationActivationController.activationPolicy(
                hasUserFacingWindows: false,
                isAwaitingWindowPresentation: true
            ),
            .regular
        )
    }

    func testTitledApplicationWindowIsUserFacing() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(ApplicationActivationController.isUserFacing(window))
    }

    func testTransientPanelDoesNotChangeApplicationActivationPolicy() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(ApplicationActivationController.isUserFacing(panel))
    }

    func testBorderlessHelperWindowIsNotUserFacing() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(ApplicationActivationController.isUserFacing(window))
    }
}
