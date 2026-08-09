import XCTest

@testable import PotliJi

final class ProductIdentityTests: XCTestCase {
    func testHostedApplicationAndTestBundleUseCanonicalIdentities() throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, AppIdentity.bundleIdentifier)
        XCTAssertEqual(
            Bundle(for: ProductIdentityTests.self).bundleIdentifier,
            AppIdentity.testsBundleIdentifier
        )
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "PotliJi")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "PotliJi")
    }

    func testEmbeddedLinkRouterExtensionsUseModuleOwnedProductsAndCanonicalBundleIdentifiers() throws {
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let expectations = [
            ("LinkRouterSafariExtension.appex", AppIdentity.safariExtensionBundleIdentifier),
            ("LinkRouterShareExtension.appex", AppIdentity.shareExtensionBundleIdentifier),
        ]

        for (productName, bundleIdentifier) in expectations {
            let bundle = try XCTUnwrap(
                Bundle(url: plugInsURL.appendingPathComponent(productName, isDirectory: true))
            )
            XCTAssertEqual(bundle.bundleIdentifier, bundleIdentifier)
            XCTAssertEqual(
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                "PotliJi Link Router"
            )
        }
    }

    func testHostRegistersCanonicalAndCompatibilityCommandSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        )
        let schemes = Set(
            urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        )

        XCTAssertTrue(schemes.contains(AppIdentity.canonicalLinkRouterScheme))
        XCTAssertTrue(schemes.contains(AppIdentity.canonicalProductScheme))
        XCTAssertTrue(schemes.contains(AppIdentity.LegacyCompatibility.linkRouterScheme))
        XCTAssertTrue(schemes.contains(AppIdentity.LegacyCompatibility.productScheme))
    }

    func testSharedAndModuleOwnedTypeNamesStaySeparated() {
        XCTAssertEqual(String(describing: AppModule.self), "AppModule")
        XCTAssertEqual(String(describing: LinkRouterModule.self), "LinkRouterModule")
        XCTAssertEqual(String(describing: PotliJiSettings.self), "PotliJiSettings")
    }
}
