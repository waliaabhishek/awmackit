import AppKit
import LinkRouterCore
import XCTest

@testable import PotliJi

final class LinkRouterCoordinatorTests: XCTestCase {
    func testPickerModifierForcesPromptAndBypassesRules() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let forcedBrowser = RouteTarget(
            id: "browser.example",
            kind: .application,
            displayName: "Example Browser"
        )
        var request = RouteRequest(
            urls: [url],
            forcedTarget: forcedBrowser,
            bypassRules: false
        )

        let applied = applyBrowserPickerModifier(
            .function,
            eventModifiers: [.function],
            to: &request
        )

        XCTAssertTrue(applied)
        XCTAssertNil(request.forcedTarget)
        XCTAssertTrue(request.forcePrompt)
        XCTAssertTrue(request.bypassRules)
    }

    func testUnheldPickerModifierLeavesRequestUnchanged() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        var request = RouteRequest(urls: [url])

        let applied = applyBrowserPickerModifier(
            .function,
            eventModifiers: [.option],
            to: &request
        )

        XCTAssertFalse(applied)
        XCTAssertFalse(request.forcePrompt)
        XCTAssertFalse(request.bypassRules)
    }

    func testCapturedModifierCanBeAppliedAfterThePhysicalKeyIsReleased() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        var request = RouteRequest(urls: [url])
        let capturedModifiers: NSEvent.ModifierFlags = [.function]

        let applied = applyBrowserPickerModifier(
            .function,
            eventModifiers: capturedModifiers,
            to: &request
        )

        XCTAssertTrue(applied)
        XCTAssertTrue(request.forcePrompt)
        XCTAssertTrue(request.bypassRules)
    }
}
