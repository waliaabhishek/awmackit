import AppKit
import LinkRouterCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var step = 0
    @State private var isDefaultBrowser = DefaultBrowserManager().isPotliJiDefaultBrowser
    @State private var isChangingDefaultBrowser = false
    @State private var defaultStatusMessage: String?

    let completion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PotliJi Link Router")
                        .font(.title.bold())
                    Text("Step \(step + 1) of 4")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(28)

            Divider()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: routingStep
                case 2: browserStep
                default: takeoverStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(32)

            Divider()

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .accessibilityLabel("Back")
                }
                Spacer()
                if step < 3 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Continue")
                } else {
                    Button("Finish") { completion() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Finish setup")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 700, minHeight: 560)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Put every link in the right place")
                .font(.largeTitle.bold())
            Text(
                "PotliJi can receive web links from macOS, clean tracking parameters, apply your rules, and then open the result in the browser, profile, or native app you choose."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            SetupRow(
                symbol: "hand.raised.fill", title: "Private by design",
                detail: "Routing, rules, and optional history stay on this Mac.")
            SetupRow(
                symbol: "arrow.triangle.branch", title: "You stay in control",
                detail: "You choose when PotliJi becomes the macOS web-link handler.")
            SetupRow(
                symbol: "menubar.rectangle", title: "Always within reach",
                detail: "Use the app, its menu-bar item, or General in Settings at any time.")
        }
    }

    private var routingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How system links are routed")
                .font(.largeTitle.bold())
            SetupRow(
                symbol: "1.circle.fill", title: "macOS hands PotliJi the link",
                detail:
                    "This applies to links opened from apps such as Mail, Messages, Notes, and Slack after you make PotliJi the default handler."
            )
            SetupRow(
                symbol: "2.circle.fill", title: "PotliJi processes it locally",
                detail: "It cleans the URL and evaluates source-app, domain, path, and modifier-key rules.")
            SetupRow(
                symbol: "3.circle.fill", title: "Your chosen destination opens",
                detail: "Use your primary browser, or hold Fn / Globe to choose from the browser picker.")
        }
    }

    private var browserStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Choose your browser behavior")
                .font(.largeTitle.bold())
            Text(
                "Choose the browser you normally use. Hold the picker modifier while opening any link whenever you want another browser."
            )
            .foregroundStyle(.secondary)
            SettingsSectionCard("Default Destination") {
                SettingsControlRow(title: "Primary browser", systemImage: "safari") {
                    RouteTargetPicker(
                        title: "Primary browser",
                        selection: linkRouterBinding(\.primaryTarget)
                    )
                    .settingsAccessoryPicker()
                }

                Divider()
                    .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)

                SettingsControlRow(title: "Browser picker shortcut", systemImage: "keyboard") {
                    Picker("Browser picker shortcut", selection: linkRouterBinding(\.browserPickerModifier)) {
                        ForEach(BrowserPickerModifier.allCases) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    .settingsAccessoryPicker()
                }

                Label(browserPickerHelpText, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
            }
        }
    }

    private var takeoverStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Allow PotliJi to receive web links")
                .font(.largeTitle.bold())
            Text(
                "The PotliJi identity is new, so macOS may still point at the previous app identifier even when your Link Router settings were migrated. Nothing changes until you press the button below. PotliJi will then ask macOS to register it for HTTP and HTTPS links. You can undo this at any time by choosing another default browser in macOS."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Label(
                isDefaultBrowser
                    ? "PotliJi is handling system web links"
                    : "Your current default browser is still handling system web links",
                systemImage: isDefaultBrowser ? "checkmark.circle.fill" : "circle.dashed"
            )
            .font(.headline)
            .foregroundStyle(isDefaultBrowser ? .green : .primary)

            Button(
                isChangingDefaultBrowser
                    ? "Waiting for macOS…"
                    : (isDefaultBrowser ? "PotliJi Is the Default" : "Use PotliJi for Web Links")
            ) {
                Task { await makeDefaultBrowser() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDefaultBrowser || isChangingDefaultBrowser)
            .accessibilityLabel(
                isDefaultBrowser ? "PotliJi is the default browser" : "Use PotliJi for web links"
            )

            if let defaultStatusMessage {
                Text(defaultStatusMessage)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(
                "You can finish without changing the default. Open General in Settings later to complete setup or route a test link."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var browserPickerHelpText: String {
        let modifier = settingsStore.settings.linkRouter.browserPickerModifier
        if modifier == .disabled {
            return "You can enable a browser-picker modifier later in General Settings."
        }
        return "Hold \(modifier.displayName) while opening a link to choose from all visible browsers and profiles."
    }

    private func linkRouterBinding<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }

    @MainActor
    private func makeDefaultBrowser() async {
        isChangingDefaultBrowser = true
        defaultStatusMessage = "macOS may ask you to confirm the default-browser change."
        defer { isChangingDefaultBrowser = false }

        do {
            try await DefaultBrowserManager().setPotliJiAsDefaultBrowser()
            isDefaultBrowser = DefaultBrowserManager().isPotliJiDefaultBrowser
            defaultStatusMessage =
                isDefaultBrowser
                ? "Setup complete. New system web links will now come through PotliJi."
                : "macOS has not switched the handler yet. Check the default-browser control in System Settings, then return here."
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct SetupRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
