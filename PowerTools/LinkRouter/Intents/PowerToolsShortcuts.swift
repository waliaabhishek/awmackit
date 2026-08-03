import AppIntents

struct PowerToolsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenURLWithPowerToolsIntent(),
            phrases: [
                "Open a link with \(.applicationName)",
                "Route a URL with \(.applicationName)",
            ],
            shortTitle: "Open URL",
            systemImageName: "arrow.triangle.branch"
        )
        AppShortcut(
            intent: CleanURLIntent(),
            phrases: [
                "Clean a link with \(.applicationName)",
                "Remove tracking with \(.applicationName)",
            ],
            shortTitle: "Clean URL",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: OpenClipboardURLIntent(),
            phrases: [
                "Open my clipboard link with \(.applicationName)"
            ],
            shortTitle: "Open Clipboard URL",
            systemImageName: "doc.on.clipboard"
        )
    }
}
