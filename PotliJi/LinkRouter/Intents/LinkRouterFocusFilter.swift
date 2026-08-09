import AppIntents

struct LinkRouterFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Choose a browser"
    static let description: LocalizedStringResource? =
        "Use a particular browser, profile, or installed web app while this Focus is active. Link rules continue to take precedence."

    @Parameter(title: "Browser or Profile")
    var browser: BrowserTargetEntity?

    var displayRepresentation: DisplayRepresentation {
        if let browser {
            return DisplayRepresentation(
                title: "Browser",
                subtitle: LocalizedStringResource(stringLiteral: browser.name)
            )
        }
        return DisplayRepresentation(title: "Browser", subtitle: "Use normal PotliJi settings")
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocusRouteOverride.targetID = browser?.id
        }
        return .result()
    }
}
