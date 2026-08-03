import LinkRouterCore
import XCTest

@testable import PowerTools

final class BrowserPresentationOrganizerTests: XCTestCase {
    func testDefaultsOnlySuggestedTargetsToVisibleAndOrdersThemByName() {
        let targets = [target("z", name: "Zeta"), target("other", name: "Other App"), target("a", name: "Alpha")]
        let suggestedIDs: Set<String> = ["a", "z"]

        let visible = BrowserPresentationOrganizer.orderedVisibleTargets(
            targets,
            presentations: [],
            defaultsToVisible: { suggestedIDs.contains($0.id) }
        )
        let normalized = BrowserPresentationOrganizer.normalizedPresentations(
            for: targets,
            presentations: [],
            defaultsToVisible: { suggestedIDs.contains($0.id) }
        )

        XCTAssertEqual(visible.map(\.id), ["a", "z"])
        XCTAssertEqual(normalized.map(\.id), ["a", "z"])
        XCTAssertEqual(normalized.map(\.order), [0, 1])
    }

    func testExplicitVisibilityOverridesSuggestedDefaults() {
        let suggested = target("browser", name: "Browser")
        let optional = target("app", name: "Optional App")
        let presentations = [
            BrowserPresentation(id: suggested.id, isShownInPrompt: false, order: 0),
            BrowserPresentation(id: optional.id, isShownInPrompt: true, order: 1),
        ]

        let visible = BrowserPresentationOrganizer.orderedVisibleTargets(
            [suggested, optional],
            presentations: presentations,
            defaultsToVisible: { $0.id == suggested.id }
        )

        XCTAssertEqual(visible.map(\.id), [optional.id])
    }

    func testVisibilityChangesPreserveShortcutAndAppendReaddedTarget() {
        let alpha = target("alpha", name: "Alpha")
        let beta = target("beta", name: "Beta")
        let presentations = [
            BrowserPresentation(id: alpha.id, promptShortcut: "a", order: 0),
            BrowserPresentation(id: beta.id, promptShortcut: "b", order: 1),
        ]
        let defaultsToVisible: (RouteTarget) -> Bool = { _ in true }

        let hidden = BrowserPresentationOrganizer.settingVisibility(
            false,
            for: alpha,
            allTargets: [alpha, beta],
            presentations: presentations,
            defaultsToVisible: defaultsToVisible
        )
        let restored = BrowserPresentationOrganizer.settingVisibility(
            true,
            for: alpha,
            allTargets: [alpha, beta],
            presentations: hidden,
            defaultsToVisible: defaultsToVisible
        )
        let visible = BrowserPresentationOrganizer.orderedVisibleTargets(
            [alpha, beta],
            presentations: restored,
            defaultsToVisible: defaultsToVisible
        )

        XCTAssertEqual(visible.map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(restored.first(where: { $0.id == alpha.id })?.promptShortcut, "a")
    }

    func testApplyingOrderUsesSequentialUniquePositions() {
        let presentations = [
            BrowserPresentation(id: "alpha", order: 8),
            BrowserPresentation(id: "beta", order: 8),
            BrowserPresentation(id: "gamma", order: 3),
        ]

        let reordered = BrowserPresentationOrganizer.applyingOrder(
            ["gamma", "alpha", "beta"],
            to: presentations
        )
        let orderByID = Dictionary(uniqueKeysWithValues: reordered.map { ($0.id, $0.order) })

        XCTAssertEqual(orderByID, ["gamma": 0, "alpha": 1, "beta": 2])
    }

    func testNormalizationKeepsLastDuplicatePresentationWithoutCrashing() {
        let alpha = target("alpha", name: "Alpha")
        let presentations = [
            BrowserPresentation(id: alpha.id, isShownInPrompt: false, order: 9),
            BrowserPresentation(id: alpha.id, isShownInPrompt: true, promptShortcut: "a", order: 2),
        ]

        let normalized = BrowserPresentationOrganizer.normalizedPresentations(
            for: [alpha],
            presentations: presentations,
            defaultsToVisible: { _ in false }
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertTrue(normalized[0].isShownInPrompt)
        XCTAssertEqual(normalized[0].promptShortcut, "a")
        XCTAssertEqual(normalized[0].order, 0)
    }

    func testShortcutNormalizationAndConflictDetection() {
        let alpha = target("alpha", name: "Alpha")
        let beta = target("beta", name: "Beta")
        let presentations = [
            BrowserPresentation(id: alpha.id, promptShortcut: "a", order: 0),
            BrowserPresentation(id: beta.id, order: 1),
        ]

        XCTAssertEqual(BrowserPresentationOrganizer.normalizedShortcut(" éF2"), "f")
        XCTAssertEqual(
            BrowserPresentationOrganizer.conflictingTargetID(
                for: "A",
                excluding: beta.id,
                visibleTargets: [alpha, beta],
                presentations: presentations
            ),
            alpha.id
        )
    }

    private func target(_ id: String, name: String) -> RouteTarget {
        RouteTarget(
            id: id,
            kind: .application,
            displayName: name,
            bundleIdentifier: "com.example.\(id)"
        )
    }
}
