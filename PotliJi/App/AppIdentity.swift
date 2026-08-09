import Foundation

enum AppIdentity {
    static let productName = "PotliJi"
    static let bundleIdentifier = "com.abhi.PotliJi"
    static let testsBundleIdentifier = "com.abhi.PotliJi.Tests"
    static let safariExtensionBundleIdentifier = "com.abhi.PotliJi.LinkRouter.SafariExtension"
    static let shareExtensionBundleIdentifier = "com.abhi.PotliJi.LinkRouter.ShareExtension"
    static let applicationSupportDirectoryName = productName
    static let canonicalLinkRouterScheme = "potliji-link"
    static let canonicalProductScheme = "potliji"

    static let onboardingVersionKey = "PotliJi.onboardingVersion"
    static let promptOriginKey = "PotliJi.LinkRouter.PromptOrigin"
    static let activeFocusTargetIDKey = "PotliJi.LinkRouter.ActiveFocusTargetID"
    static let selectedSettingsPaneKey = "settings.selectedPane"

    /// Historical identifiers retained solely to migrate existing installations and
    /// accept commands created before the PotliJi rename.
    enum LegacyCompatibility {
        static let bundleIdentifier = "com.abhi.PowerTools"
        static let applicationSupportDirectoryName = "PowerTools"
        static let linkRouterScheme = "powertools-link"
        static let productScheme = "powertools"
        static let onboardingVersionKey = "PowerTools.onboardingVersion"
        static let promptOriginKey = "PowerTools.LinkRouter.PromptOrigin"
        static let activeFocusTargetIDKey = "PowerTools.LinkRouter.ActiveFocusTargetID"
    }
}
