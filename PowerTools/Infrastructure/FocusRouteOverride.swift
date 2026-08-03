import Foundation
import LinkRouterCore

/// Stores the browser selected by the currently active Focus filter.
/// The value is deliberately transient configuration rather than part of the exported user settings.
@MainActor
enum FocusRouteOverride {
    private static let targetIDKey = "PowerTools.LinkRouter.ActiveFocusTargetID"

    static var targetID: String? {
        get { UserDefaults.standard.string(forKey: targetIDKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: targetIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: targetIDKey)
            }
        }
    }

    static func target(in catalog: BrowserCatalog) -> RouteTarget? {
        guard let targetID else { return nil }
        return catalog.target(withID: targetID)
    }
}
