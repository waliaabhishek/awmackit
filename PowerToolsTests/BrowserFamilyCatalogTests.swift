import XCTest

@testable import PowerTools

final class BrowserFamilyCatalogTests: XCTestCase {
    func testPrivateTargetsExcludeSafariAutomation() {
        XCTAssertFalse(BrowserFamilyCatalog.supportsPrivateWindows("com.apple.Safari"))
        XCTAssertTrue(BrowserFamilyCatalog.supportsPrivateWindows("com.google.Chrome"))
        XCTAssertTrue(BrowserFamilyCatalog.supportsPrivateWindows("org.mozilla.firefox"))
    }
}
