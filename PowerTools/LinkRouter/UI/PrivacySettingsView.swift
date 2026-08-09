import AppKit
import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var showsAdvancedSettings = false
    @State private var confirmsClearingHistory = false
    @State private var confirmsClipboardMonitoring = false
    @State private var historyRecoveryError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
                SettingsPageHeader(
                    title: "Privacy",
                    subtitle: "Keep links cleaner and control what Power Tools remembers."
                )

                linkProtectionCard
                    .alert("Allow Automatic Clipboard Cleaning?", isPresented: $confirmsClipboardMonitoring) {
                        Button("Cancel", role: .cancel) {}
                        Button("Turn On") { enableClipboardCleaning() }
                    } message: {
                        Text(
                            "Power Tools will check newly copied text for web links. On current macOS releases, the system asks before allowing the first matching clipboard read. Nothing is uploaded."
                        )
                    }
                historyCard
                advancedCard

                Label(
                    "Link cleaning and history stay on this Mac. Revealing shortened links may contact the link service.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showsAdvancedSettings) {
            AdvancedPrivacySettingsView()
        }
        .alert("Clear Link History?", isPresented: $confirmsClearingHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                Task { await historyStore.clear() }
            }
        } message: {
            Text("This permanently removes every saved link from this Mac.")
        }
        .alert(
            "History Recovery Failed",
            isPresented: Binding(
                get: { historyRecoveryError != nil },
                set: { if !$0 { historyRecoveryError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { historyRecoveryError = nil }
        } message: {
            Text(historyRecoveryError ?? "The history file could not be recovered.")
        }
    }

    private var linkProtectionCard: some View {
        SettingsSectionCard("Link Protection") {
            SettingsToggleRow(
                title: "Protect links from tracking",
                detail: "Removes known tracking details and unwraps common tracking redirects before routing.",
                systemImage: "shield.lefthalf.filled",
                isOn: trackingProtection
            )

            alignedDivider

            SettingsToggleRow(
                title: "Clean links when copied",
                detail: "Automatically cleans a copied web link before you paste or share it.",
                systemImage: "clipboard",
                isOn: cleanCopiedLinks
            )
            .disabled(!trackingProtection.wrappedValue)

            if clipboardAccessIsDenied {
                Label(
                    "Pasteboard access is denied. Automatic cleaning will stay off until access is changed in System Settings.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
            }

            alignedDivider

            SettingsToggleRow(
                title: "Reveal shortened-link destinations",
                detail: "Lets routing rules use the final destination for recognized short-link services.",
                systemImage: "arrow.up.left.and.arrow.down.right",
                isOn: setting(\.expandShortURLs)
            )
        }
    }

    private var historyCard: some View {
        SettingsSectionCard("History") {
            if let issue = historyStore.loadIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Back Up & Reset History…") {
                        backUpAndResetHistory()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)

                alignedDivider
            } else if let persistenceError = historyStore.lastPersistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)

                alignedDivider
            }

            SettingsToggleRow(
                title: "Remember opened links",
                detail: historyDetail,
                systemImage: "clock.arrow.circlepath",
                isOn: setting(\.historyEnabled)
            )
            .disabled(historyStore.loadIssue != nil)

            if !historyStore.entries.isEmpty {
                alignedDivider

                HStack(spacing: 10) {
                    Text(historyCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open History") {
                        WindowPresenter.shared.showHistory()
                    }
                    .buttonStyle(.bordered)

                    Button("Clear…", role: .destructive) {
                        confirmsClearingHistory = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
            }
        }
    }

    private var advancedCard: some View {
        SettingsSectionCard("Advanced") {
            SettingsActionRow(
                title: "Advanced privacy controls",
                detail: "Fine-tune link cleaning, shortened-link checks, and local storage limits.",
                systemImage: "slider.horizontal.3",
                buttonTitle: "Advanced…"
            ) {
                showsAdvancedSettings = true
            }
        }
    }

    private var alignedDivider: some View {
        Divider()
            .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
    }

    private var historyDetail: String {
        let count = historyStore.entries.count
        if settingsStore.settings.linkRouter.historyEnabled {
            return count == 0
                ? "Saved only on this Mac. No links have been remembered yet."
                : "Saved only on this Mac."
        }
        return count == 0
            ? "New links won’t be saved."
            : "New links won’t be saved. Existing history remains until you clear it."
    }

    private var historyCountLabel: String {
        let count = historyStore.entries.count
        let noun = count == 1 ? "link" : "links"
        return "\(count) \(noun) saved"
    }

    private var trackingProtection: Binding<Bool> {
        Binding(
            get: {
                settingsStore.settings.linkRouter.removeTrackingParameters
                    || settingsStore.settings.linkRouter.unwrapEmbeddedRedirects
            },
            set: { isEnabled in
                settingsStore.settings.linkRouter.removeTrackingParameters = isEnabled
                settingsStore.settings.linkRouter.unwrapEmbeddedRedirects = isEnabled
                if !isEnabled {
                    settingsStore.settings.linkRouter.cleanCopiedLinks = false
                    environment.pasteboardMonitor.stop()
                }
            }
        )
    }

    private var cleanCopiedLinks: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.linkRouter.cleanCopiedLinks },
            set: { isEnabled in
                if isEnabled {
                    confirmsClipboardMonitoring = true
                } else {
                    settingsStore.settings.linkRouter.cleanCopiedLinks = false
                    environment.pasteboardMonitor.stop()
                }
            }
        )
    }

    private var clipboardAccessIsDenied: Bool {
        if #available(macOS 15.4, *) {
            return NSPasteboard.general.accessBehavior == .alwaysDeny
        }
        return false
    }

    private func enableClipboardCleaning() {
        guard !clipboardAccessIsDenied else {
            let alert = NSAlert()
            alert.messageText = "Pasteboard Access Is Off"
            alert.informativeText =
                "Allow Power Tools under System Settings > Privacy & Security > Pasteboard, then turn automatic cleaning on again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        settingsStore.settings.linkRouter.cleanCopiedLinks = true
        environment.pasteboardMonitor.startIfNeeded()
    }

    private func backUpAndResetHistory() {
        Task { @MainActor in
            do {
                _ = try await historyStore.backUpAndResetAfterLoadFailure()
            } catch {
                historyRecoveryError = error.localizedDescription
            }
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }
}

private struct AdvancedPrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
                    cleaningCard
                    trackingOverridesCard
                    shortenedLinksCard
                    storageCard
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 600)
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Advanced Privacy")
                    .font(.title2.bold())
                Text("Fine-tune how links are cleaned, resolved, and retained.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var cleaningCard: some View {
        SettingsSectionCard("Link Cleaning") {
            SettingsToggleRow(
                title: "Remove known tracking parameters",
                detail: "Removes recognized campaign and tracking fields from web addresses.",
                systemImage: "line.3.horizontal.decrease.circle",
                isOn: setting(\.removeTrackingParameters)
            )

            alignedDivider

            SettingsToggleRow(
                title: "Unwrap embedded redirect links",
                detail: "Extracts the real destination from recognized tracking redirect links.",
                systemImage: "link",
                isOn: setting(\.unwrapEmbeddedRedirects)
            )
        }
    }

    private var trackingOverridesCard: some View {
        SettingsSectionCard("Tracking Overrides") {
            SettingsControlRow(
                title: "Also remove",
                detail: "Additional query-parameter names, one per line.",
                systemImage: "minus.circle",
                accessoryWidth: 340
            ) {
                MultilineListEditor(
                    values: setting(\.additionalTrackingParameters),
                    placeholder: "parameter_name\nanother_parameter"
                )
                .frame(height: 76)
            }

            alignedDivider

            SettingsControlRow(
                title: "Always keep",
                detail: "Required parameters that Power Tools must never remove.",
                systemImage: "checkmark.circle",
                accessoryWidth: 340
            ) {
                MultilineListEditor(
                    values: setting(\.allowedTrackingParameters),
                    placeholder: "required_parameter"
                )
                .frame(height: 76)
            }

            Text("Always Keep takes precedence when the same parameter appears in both lists.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
        }
        .disabled(!settingsStore.settings.linkRouter.removeTrackingParameters)
    }

    private var shortenedLinksCard: some View {
        SettingsSectionCard("Shortened Links") {
            SettingsControlRow(
                title: "Maximum redirects",
                detail:
                    "Stops after this many trusted shortener-to-shortener hops. The final destination is opened by your browser, not fetched by Power Tools.",
                systemImage: "point.3.connected.trianglepath.dotted",
                accessoryWidth: 180
            ) {
                HStack(spacing: 8) {
                    Text(settingsStore.settings.linkRouter.shortURLRedirectLimit, format: .number)
                        .monospacedDigit()
                        .frame(minWidth: 24, alignment: .trailing)
                    Stepper(
                        "Maximum redirects",
                        value: setting(\.shortURLRedirectLimit),
                        in: 1...50
                    )
                    .labelsHidden()
                }
                .fixedSize()
            }
            .disabled(!settingsStore.settings.linkRouter.expandShortURLs)

            if !settingsStore.settings.linkRouter.expandShortURLs {
                Text("Turn on Reveal shortened-link destinations on the main Privacy page to use these controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
            }
        }
    }

    private var storageCard: some View {
        SettingsSectionCard("History & Storage") {
            SettingsControlRow(
                title: "History limit",
                detail: "Older entries are removed automatically when this limit is reached.",
                systemImage: "clock.arrow.circlepath",
                accessoryWidth: 220
            ) {
                HStack(spacing: 8) {
                    Text(settingsStore.settings.linkRouter.historyLimit, format: .number)
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                    Stepper(
                        "History limit",
                        value: setting(\.historyLimit),
                        in: 25...5_000,
                        step: 25
                    )
                    .labelsHidden()
                }
                .fixedSize()
            }
            .disabled(!settingsStore.settings.linkRouter.historyEnabled)

            alignedDivider

            SettingsActionRow(
                title: "Power Tools data",
                detail: "Reveal the local folder containing settings and link history.",
                systemImage: "folder",
                buttonTitle: "Show in Finder"
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([settingsStore.settingsURL])
            }
        }
    }

    private var alignedDivider: some View {
        Divider()
            .padding(.leading, SettingsDesign.iconColumnWidth + SettingsDesign.rowSpacing)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<LinkRouterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings.linkRouter[keyPath: keyPath] },
            set: { settingsStore.settings.linkRouter[keyPath: keyPath] = $0 }
        )
    }
}

private struct MultilineListEditor: View {
    @Binding var values: [String]
    let placeholder: String
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .focused($isFocused)

            if draft.isEmpty {
                Text(placeholder)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .onAppear {
            draft = values.joined(separator: "\n")
        }
        .onChange(of: draft) { _, newValue in
            values = parsedValues(from: newValue)
        }
        .onChange(of: values) { _, newValues in
            guard !isFocused else { return }
            let normalized = newValues.joined(separator: "\n")
            if draft != normalized {
                draft = normalized
            }
        }
        .onChange(of: isFocused) { _, hasFocus in
            guard !hasFocus else { return }
            draft = values.joined(separator: "\n")
        }
    }

    private func parsedValues(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
