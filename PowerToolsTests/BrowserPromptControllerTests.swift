import AppKit
import LinkRouterCore
import XCTest

@testable import PowerTools

@MainActor
final class BrowserPromptControllerTests: XCTestCase {
    func testPickerKeepsItsConfiguredWindowSize() async throws {
        let controller = BrowserPromptController()
        let target = RouteTarget(
            id: "test.browser",
            kind: .application,
            displayName: "Test Browser"
        )
        let url = try XCTUnwrap(URL(string: "https://example.com/"))
        let selectionTask = Task {
            await controller.choose(
                url: url,
                targets: [target],
                presentation: [],
                showsURL: true,
                allowActions: false,
                controlOpensInBackground: false,
                preservePosition: false
            )
        }

        let panel = try await waitForPromptPanel()
        XCTAssertEqual(panel.contentLayoutRect.width, 380, accuracy: 1)
        XCTAssertEqual(panel.contentLayoutRect.height, 190, accuracy: 1)

        let returnEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            ))
        NSApp.sendEvent(returnEvent)

        let selection = await selectionTask.value
        XCTAssertEqual(selection?.target, target)
        XCTAssertFalse(panel.isVisible)
    }

    private func waitForPromptPanel() async throws -> NSWindow {
        for _ in 0..<100 {
            if let panel = NSApp.windows.first(where: {
                $0.identifier?.rawValue == "PowerTools.BrowserPrompt"
            }) {
                return panel
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(
            .coderValueNotFound,
            userInfo: [NSLocalizedDescriptionKey: "The browser prompt panel was not presented."]
        )
    }
}
