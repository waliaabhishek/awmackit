import XCTest

@testable import PotliJi

final class BrowserFamilyCatalogTests: XCTestCase {
    @MainActor
    func testApplicationsOnlyDiscoveryDoesNotBlockOnProfilesOrPWAs() async {
        let catalog = BrowserCatalog()

        await catalog.loadApplicationsIfNeeded()

        XCTAssertTrue(catalog.profiles.isEmpty)
        XCTAssertTrue(catalog.pwas.isEmpty)
    }

    func testPrivateTargetsExcludeSafariAutomation() {
        XCTAssertFalse(BrowserFamilyCatalog.supportsPrivateWindows("com.apple.Safari"))
        XCTAssertTrue(BrowserFamilyCatalog.supportsPrivateWindows("com.google.Chrome"))
        XCTAssertTrue(BrowserFamilyCatalog.supportsPrivateWindows("org.mozilla.firefox"))
    }

    func testVivaldiUsesArgumentsForColdStartAndExecutableHandoffWhenRunning() {
        XCTAssertEqual(
            BrowserLauncher.applicationURLDelivery(
                bundleIdentifier: "com.vivaldi.Vivaldi",
                isRunning: false
            ),
            .launchWithArguments
        )
        XCTAssertEqual(
            BrowserLauncher.applicationURLDelivery(
                bundleIdentifier: "com.vivaldi.Vivaldi",
                isRunning: true
            ),
            .executableHandoff
        )
    }

    func testSafariKeepsWorkspaceURLDelivery() {
        XCTAssertEqual(
            BrowserLauncher.applicationURLDelivery(
                bundleIdentifier: "com.apple.Safari",
                isRunning: false
            ),
            .workspaceURLs
        )
        XCTAssertEqual(
            BrowserLauncher.applicationURLDelivery(
                bundleIdentifier: "com.apple.Safari",
                isRunning: true
            ),
            .workspaceURLs
        )
    }

    func testBrowserArgumentsAreSharedAcrossApplicationAndProfileDelivery() throws {
        let first = try XCTUnwrap(URL(string: "https://example.com/one"))
        let second = try XCTUnwrap(URL(string: "https://example.com/two"))

        XCTAssertEqual(
            BrowserLauncher.browserArguments(
                urls: [first, second],
                bundleIdentifier: "com.vivaldi.Vivaldi",
                profileIdentifier: "Profile 2",
                openMode: .privateWindow,
                newWindow: true
            ),
            [
                "--profile-directory=Profile 2",
                "--incognito",
                "--new-window",
                first.absoluteString,
                second.absoluteString,
            ]
        )
        XCTAssertEqual(
            BrowserLauncher.browserArguments(
                urls: [first, second],
                bundleIdentifier: "org.mozilla.firefox"
            ),
            ["-new-tab", first.absoluteString, "-new-tab", second.absoluteString]
        )
    }
}
