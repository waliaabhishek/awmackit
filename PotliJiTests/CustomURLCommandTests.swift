import XCTest

@testable import PotliJi

@MainActor
final class CustomURLCommandTests: XCTestCase {
    func testCanonicalAndLegacySchemesUseTheSameLinkRouterCommandParser() throws {
        let schemes = [
            AppIdentity.canonicalLinkRouterScheme,
            AppIdentity.canonicalProductScheme,
            AppIdentity.LegacyCompatibility.linkRouterScheme,
            AppIdentity.LegacyCompatibility.productScheme,
        ]
        let catalog = BrowserCatalog()

        for scheme in schemes {
            let url = try XCTUnwrap(
                URL(string: "\(scheme)://open?source=browser-extension&prompt=1&url=https%3A%2F%2Fexample.com")
            )
            XCTAssertTrue(CustomURLCommand.supports(url))
            let command = try CustomURLCommand(url: url, browserCatalog: catalog)
            guard case .open(let request) = command.action else {
                return XCTFail("Expected an open command for \(scheme).")
            }
            XCTAssertEqual(request.urls, [URL(string: "https://example.com")!])
            XCTAssertEqual(request.trigger, .browserExtension)
            XCTAssertTrue(request.forcePrompt)
        }
    }

    func testUnrelatedSchemeIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "other-product://open?url=https%3A%2F%2Fexample.com"))
        XCTAssertFalse(CustomURLCommand.supports(url))
        XCTAssertThrowsError(try CustomURLCommand(url: url, browserCatalog: BrowserCatalog()))
    }
}
