import XCTest

@testable import LinkRouterCore

final class SafetyAndConcurrencyTests: XCTestCase {
    func testRejectsPrivateAndReservedIPv4Addresses() {
        let blocked: [[UInt8]] = [
            [0, 0, 0, 0], [10, 0, 0, 1], [100, 64, 0, 1], [127, 0, 0, 1],
            [169, 254, 1, 1], [172, 16, 0, 1], [192, 168, 1, 1], [224, 0, 0, 1],
        ]
        for address in blocked {
            XCTAssertFalse(PublicNetworkHostValidator.isPublicAddress(address), "Unexpectedly allowed \(address)")
        }
        XCTAssertTrue(PublicNetworkHostValidator.isPublicAddress([8, 8, 8, 8]))
    }

    func testRejectsPrivateIPv6AndMappedLoopbackAddresses() {
        var loopback = [UInt8](repeating: 0, count: 16)
        loopback[15] = 1
        var uniqueLocal = [UInt8](repeating: 0, count: 16)
        uniqueLocal[0] = 0xfc
        var linkLocal = [UInt8](repeating: 0, count: 16)
        linkLocal[0] = 0xfe
        linkLocal[1] = 0x80
        let mappedLoopback = [UInt8](repeating: 0, count: 10) + [0xff, 0xff, 127, 0, 0, 1]

        for address in [loopback, uniqueLocal, linkLocal, mappedLoopback] {
            XCTAssertFalse(PublicNetworkHostValidator.isPublicAddress(address))
        }

        let publicAddress: [UInt8] = [
            0x26, 0x06, 0x47, 0x00, 0x47, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11, 0x11,
        ]
        XCTAssertTrue(PublicNetworkHostValidator.isPublicAddress(publicAddress))
    }

    func testAsyncGateResumesWaitersInFIFOOrder() async {
        let gate = AsyncGate()
        let recorder = Recorder()
        await gate.enter()

        let first = Task {
            await gate.enter()
            await recorder.append(1)
            await gate.leave()
        }
        await Task.yield()
        let second = Task {
            await gate.enter()
            await recorder.append(2)
            await gate.leave()
        }
        try? await Task.sleep(for: .milliseconds(10))
        await gate.leave()
        _ = await (first.value, second.value)

        let values = await recorder.values
        XCTAssertEqual(values, [1, 2])
    }

    func testRuleTransferRejectsInvalidRegexAndOversizedScripts() {
        let invalidRegex = LinkRule(
            name: "Invalid regex",
            urlMatchers: [URLMatcher(kind: .regularExpression, pattern: "[")],
            target: .primary
        )
        XCTAssertThrowsError(try RuleTransfer().encode([invalidRegex]))

        let oversizedScript = LinkRule(
            name: "Oversized script",
            target: .primary,
            transformJavaScript: String(repeating: "x", count: RuleTransfer.maximumScriptBytes + 1)
        )
        XCTAssertThrowsError(try RuleTransfer().encode([oversizedScript]))

        let oversizedDocument = Data(count: RuleTransfer.maximumDocumentBytes + 1)
        XCTAssertThrowsError(try RuleTransfer().decode(oversizedDocument))
    }

    func testRuleTransferRoundTripsGuidedConditionsAndRewrites() throws {
        let rule = LinkRule(
            name: "Open social links privately",
            urlMatcherGroups: [
                URLMatcherGroup(
                    mode: .any,
                    matchers: [
                        URLMatcher(kind: .hostSuffix, pattern: "x.com"),
                        URLMatcher(kind: .hostSuffix, pattern: "twitter.com"),
                    ]
                )
            ],
            target: .prompt,
            rewriteActions: [URLRewriteAction(kind: .replaceHost, value: "xcancel.com")],
            editorKind: .guided,
            websiteFamilyID: "x-twitter"
        )

        let decoded = try RuleTransfer().decode(RuleTransfer().encode([rule]))

        let transferred = try XCTUnwrap(decoded.first)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(transferred.id, rule.id)
        XCTAssertEqual(transferred.urlMatcherGroups, rule.urlMatcherGroups)
        XCTAssertEqual(transferred.target, rule.target)
        XCTAssertEqual(transferred.rewriteActions, rule.rewriteActions)
        XCTAssertEqual(transferred.editorKind, .guided)
        XCTAssertEqual(transferred.websiteFamilyID, "x-twitter")
    }
}

private actor Recorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}
