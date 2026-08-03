import Foundation
import LinkRouterCore

enum BrowserPresentationOrganizer {
    static func orderedVisibleTargets(
        _ targets: [RouteTarget],
        presentations: [BrowserPresentation],
        defaultsToVisible: (RouteTarget) -> Bool
    ) -> [RouteTarget] {
        let presentationByID = presentationsByID(presentations)
        return
            targets
            .filter { target in
                presentationByID[target.id]?.isShownInPrompt ?? defaultsToVisible(target)
            }
            .sorted { lhs, rhs in
                let lhsOrder = presentationByID[lhs.id]?.order ?? Int.max
                let rhsOrder = presentationByID[rhs.id]?.order ?? Int.max
                if lhsOrder == rhsOrder {
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                return lhsOrder < rhsOrder
            }
    }

    static func normalizedPresentations(
        for targets: [RouteTarget],
        presentations: [BrowserPresentation],
        defaultsToVisible: (RouteTarget) -> Bool
    ) -> [BrowserPresentation] {
        let visibleTargets = orderedVisibleTargets(
            targets,
            presentations: presentations,
            defaultsToVisible: defaultsToVisible
        )
        var result = deduplicated(presentations)
        for (order, target) in visibleTargets.enumerated() {
            var presentation = presentation(
                for: target,
                presentations: result,
                defaultsToVisible: defaultsToVisible
            )
            presentation.order = order
            result = replacing(presentation, in: result)
        }
        return result
    }

    static func settingVisibility(
        _ isVisible: Bool,
        for target: RouteTarget,
        allTargets: [RouteTarget],
        presentations: [BrowserPresentation],
        defaultsToVisible: (RouteTarget) -> Bool
    ) -> [BrowserPresentation] {
        var result = normalizedPresentations(
            for: allTargets,
            presentations: presentations,
            defaultsToVisible: defaultsToVisible
        )
        var updated = presentation(
            for: target,
            presentations: result,
            defaultsToVisible: defaultsToVisible
        )
        updated.isShownInPrompt = isVisible
        if isVisible {
            updated.order =
                orderedVisibleTargets(
                    allTargets,
                    presentations: result,
                    defaultsToVisible: defaultsToVisible
                ).count
        }
        result = replacing(updated, in: result)
        return normalizedPresentations(
            for: allTargets,
            presentations: result,
            defaultsToVisible: defaultsToVisible
        )
    }

    static func applyingOrder(
        _ orderedTargetIDs: [String],
        to presentations: [BrowserPresentation]
    ) -> [BrowserPresentation] {
        var result = deduplicated(presentations)
        for (order, id) in orderedTargetIDs.enumerated() {
            guard var item = result.first(where: { $0.id == id }) else { continue }
            item.order = order
            result = replacing(item, in: result)
        }
        return result
    }

    static func settingShortcut(
        _ shortcut: String?,
        for target: RouteTarget,
        presentations: [BrowserPresentation],
        defaultsToVisible: (RouteTarget) -> Bool
    ) -> [BrowserPresentation] {
        var item = presentation(
            for: target,
            presentations: presentations,
            defaultsToVisible: defaultsToVisible
        )
        item.promptShortcut = shortcut.flatMap(normalizedShortcut)
        return replacing(item, in: deduplicated(presentations))
    }

    static func conflictingTargetID(
        for shortcut: String,
        excluding targetID: String,
        visibleTargets: [RouteTarget],
        presentations: [BrowserPresentation]
    ) -> String? {
        guard let normalized = normalizedShortcut(shortcut) else { return nil }
        let presentationByID = presentationsByID(presentations)
        return visibleTargets.first { target in
            guard target.id != targetID,
                let candidate = presentationByID[target.id]?.promptShortcut.flatMap(normalizedShortcut)
            else {
                return false
            }
            return candidate == normalized
        }?.id
    }

    static func normalizedShortcut(_ value: String) -> String? {
        for scalar in value.lowercased().unicodeScalars
        where scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
            return String(scalar)
        }
        return nil
    }

    static func presentation(
        for target: RouteTarget,
        presentations: [BrowserPresentation],
        defaultsToVisible: (RouteTarget) -> Bool
    ) -> BrowserPresentation {
        presentations.last(where: { $0.id == target.id })
            ?? BrowserPresentation(
                id: target.id,
                isShownInPrompt: defaultsToVisible(target),
                order: Int.max
            )
    }

    private static func presentationsByID(
        _ presentations: [BrowserPresentation]
    ) -> [String: BrowserPresentation] {
        presentations.reduce(into: [:]) { result, presentation in
            result[presentation.id] = presentation
        }
    }

    private static func deduplicated(
        _ presentations: [BrowserPresentation]
    ) -> [BrowserPresentation] {
        var result: [BrowserPresentation] = []
        for presentation in presentations {
            result = replacing(presentation, in: result)
        }
        return result
    }

    private static func replacing(
        _ presentation: BrowserPresentation,
        in presentations: [BrowserPresentation]
    ) -> [BrowserPresentation] {
        var result = presentations
        if let index = result.firstIndex(where: { $0.id == presentation.id }) {
            result.removeAll { $0.id == presentation.id }
            result.insert(presentation, at: min(index, result.count))
        } else {
            result.append(presentation)
        }
        return result
    }
}
