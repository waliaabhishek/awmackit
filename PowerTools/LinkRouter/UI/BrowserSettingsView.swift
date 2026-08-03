import AppKit
import LinkRouterCore
import SwiftUI

struct BrowserSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var browserCatalog: BrowserCatalog
    @State private var showsAddDestinations = false
    @State private var shortcutTargetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: "Browser Picker",
                subtitle:
                    "Choose and arrange the destinations that appear when you ask Power Tools where to open a link."
            )

            List {
                Section {
                    if visibleTargets.isEmpty {
                        emptyPickerRow
                    } else {
                        ForEach(visibleTargets) { target in
                            pickerRow(target)
                        }
                        .onMove(perform: moveVisibleTargets)
                    }
                } header: {
                    HStack {
                        Text("In Browser Picker")
                        Spacer()
                        Text(destinationCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                } footer: {
                    if !visibleTargets.isEmpty {
                        Text("Drag to reorder. Select a key badge to assign a one-key shortcut.")
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: pickerListHeight)

            HStack {
                Button {
                    showsAddDestinations = true
                } label: {
                    Label("Add Destinations…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                if browserCatalog.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating destinations…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showsAddDestinations) {
            AddBrowserDestinationsView(onAdd: addToPicker)
                .environmentObject(settingsStore)
                .environmentObject(browserCatalog)
        }
        .task {
            await settingsStore.loadIfNeeded()
            await browserCatalog.loadIfNeeded()
            normalizePresentations()
        }
        .onChange(of: browserCatalog.allTargets.map(\.id)) { _, _ in
            normalizePresentations()
        }
    }

    private var visibleTargets: [RouteTarget] {
        BrowserPresentationOrganizer.orderedVisibleTargets(
            browserCatalog.allTargets,
            presentations: settingsStore.settings.linkRouter.browserPresentation,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        )
    }

    private var destinationCountLabel: String {
        "\(visibleTargets.count) \(visibleTargets.count == 1 ? "destination" : "destinations")"
    }

    private var pickerListHeight: CGFloat {
        min(max(CGFloat(visibleTargets.count) * 50 + 100, 170), 390)
    }

    private var emptyPickerRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Your browser picker is empty")
                .font(.headline)
            Text("Add at least one destination to choose where links open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func pickerRow(_ target: RouteTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
                .accessibilityHidden(true)

            Image(nsImage: browserCatalog.icon(for: target))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName)
                    .lineLimit(1)
                Text(BrowserDestinationPresentation.detail(for: target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            shortcutButton(for: target)

            Menu {
                let index = visibleTargets.firstIndex(where: { $0.id == target.id }) ?? 0
                Button("Move Up") { moveTarget(target, by: -1) }
                    .disabled(index == 0)
                Button("Move Down") { moveTarget(target, by: 1) }
                    .disabled(index >= visibleTargets.count - 1)

                if shortcut(for: target) != nil {
                    Divider()
                    Button("Clear Shortcut") { setShortcut(nil, for: target) }
                }

                Divider()
                Button("Remove from Browser Picker") { removeFromPicker(target) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More options for \(target.displayName)")
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private func shortcutButton(for target: RouteTarget) -> some View {
        Button {
            shortcutTargetID = target.id
        } label: {
            Group {
                if let shortcut = shortcut(for: target) {
                    Text(shortcut.uppercased())
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                } else {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 28, minHeight: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help(shortcut(for: target) == nil ? "Assign a keyboard shortcut" : "Change keyboard shortcut")
        .accessibilityLabel("Keyboard shortcut for \(target.displayName)")
        .accessibilityValue(shortcut(for: target)?.uppercased() ?? "Not assigned")
        .popover(isPresented: shortcutPopoverBinding(for: target.id), arrowEdge: .leading) {
            BrowserShortcutEditor(
                targetName: target.displayName,
                initialShortcut: shortcut(for: target),
                reservedShortcuts: reservedShortcuts(excluding: target.id),
                onSave: { shortcut in
                    setShortcut(shortcut, for: target)
                }
            )
            .id(target.id)
        }
    }

    private func shortcutPopoverBinding(for targetID: String) -> Binding<Bool> {
        Binding(
            get: { shortcutTargetID == targetID },
            set: { isPresented in
                if !isPresented, shortcutTargetID == targetID {
                    shortcutTargetID = nil
                }
            }
        )
    }

    private func shortcut(for target: RouteTarget) -> String? {
        BrowserPresentationOrganizer.presentation(
            for: target,
            presentations: settingsStore.settings.linkRouter.browserPresentation,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        ).promptShortcut
    }

    private func reservedShortcuts(excluding targetID: String) -> [String: String] {
        visibleTargets.reduce(into: [:]) { result, target in
            guard target.id != targetID,
                let shortcut = shortcut(for: target).flatMap(BrowserPresentationOrganizer.normalizedShortcut)
            else {
                return
            }
            result[shortcut] = target.displayName
        }
    }

    private func normalizePresentations() {
        let current = settingsStore.settings.linkRouter.browserPresentation
        let normalized = BrowserPresentationOrganizer.normalizedPresentations(
            for: browserCatalog.allTargets,
            presentations: current,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        )
        if normalized != current {
            settingsStore.settings.linkRouter.browserPresentation = normalized
        }
    }

    private func moveVisibleTargets(from source: IndexSet, to destination: Int) {
        var reordered = visibleTargets
        reordered.move(fromOffsets: source, toOffset: destination)
        applyOrder(reordered)
    }

    private func moveTarget(_ target: RouteTarget, by offset: Int) {
        var reordered = visibleTargets
        guard let sourceIndex = reordered.firstIndex(where: { $0.id == target.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard reordered.indices.contains(destinationIndex) else { return }
        reordered.swapAt(sourceIndex, destinationIndex)
        applyOrder(reordered)
    }

    private func applyOrder(_ targets: [RouteTarget]) {
        settingsStore.settings.linkRouter.browserPresentation = BrowserPresentationOrganizer.applyingOrder(
            targets.map(\.id),
            to: settingsStore.settings.linkRouter.browserPresentation
        )
    }

    private func addToPicker(_ target: RouteTarget) {
        settingsStore.settings.linkRouter.browserPresentation = BrowserPresentationOrganizer.settingVisibility(
            true,
            for: target,
            allTargets: browserCatalog.allTargets,
            presentations: settingsStore.settings.linkRouter.browserPresentation,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        )
        clearShortcutIfConflicting(for: target)
    }

    private func removeFromPicker(_ target: RouteTarget) {
        settingsStore.settings.linkRouter.browserPresentation = BrowserPresentationOrganizer.settingVisibility(
            false,
            for: target,
            allTargets: browserCatalog.allTargets,
            presentations: settingsStore.settings.linkRouter.browserPresentation,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        )
    }

    private func setShortcut(_ shortcut: String?, for target: RouteTarget) {
        settingsStore.settings.linkRouter.browserPresentation = BrowserPresentationOrganizer.settingShortcut(
            shortcut,
            for: target,
            presentations: settingsStore.settings.linkRouter.browserPresentation,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        )
    }

    private func clearShortcutIfConflicting(for target: RouteTarget) {
        guard let targetShortcut = shortcut(for: target),
            BrowserPresentationOrganizer.conflictingTargetID(
                for: targetShortcut,
                excluding: target.id,
                visibleTargets: visibleTargets,
                presentations: settingsStore.settings.linkRouter.browserPresentation
            ) != nil
        else {
            return
        }
        setShortcut(nil, for: target)
    }
}

private struct BrowserShortcutEditor: View {
    let targetName: String
    let initialShortcut: String?
    let reservedShortcuts: [String: String]
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldIsFocused: Bool
    @State private var draft: String

    init(
        targetName: String,
        initialShortcut: String?,
        reservedShortcuts: [String: String],
        onSave: @escaping (String?) -> Void
    ) {
        self.targetName = targetName
        self.initialShortcut = initialShortcut
        self.reservedShortcuts = reservedShortcuts
        self.onSave = onSave
        _draft = State(initialValue: initialShortcut?.uppercased() ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keyboard Shortcut")
                    .font(.headline)
                Text(targetName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("None", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .focused($fieldIsFocused)
                .onChange(of: draft) { _, value in
                    let sanitized = BrowserPresentationOrganizer.normalizedShortcut(value)?.uppercased() ?? ""
                    if sanitized != value {
                        draft = sanitized
                    }
                }
                .onSubmit(save)

            if let conflictName {
                Label("Already assigned to \(conflictName)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Enter one letter or number.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Clear") {
                    onSave(nil)
                    dismiss()
                }
                .disabled(initialShortcut == nil && draft.isEmpty)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                Button("Done", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(conflictName != nil)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { fieldIsFocused = true }
    }

    private var normalizedDraft: String? {
        BrowserPresentationOrganizer.normalizedShortcut(draft)
    }

    private var conflictName: String? {
        normalizedDraft.flatMap { reservedShortcuts[$0] }
    }

    private func save() {
        guard conflictName == nil else { return }
        onSave(normalizedDraft)
        dismiss()
    }
}

private struct AddBrowserDestinationsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var browserCatalog: BrowserCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let onAdd: (RouteTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Destinations")
                        .font(.title2.bold())
                    Text("Choose additional browsers, profiles, private windows, or apps for the picker.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await browserCatalog.refresh() }
                } label: {
                    if browserCatalog.isRefreshing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning…")
                        }
                    } else {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(browserCatalog.isRefreshing)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Search destinations", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if availableTargets.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Everything Is Already Added" : "No Destinations Found",
                    systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Rescan if you recently installed another browser or app."
                            : "Try another name or clear the search field."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    destinationSection("Browsers", targets: browserTargets)
                    destinationSection("Profiles", targets: profileTargets)
                    destinationSection("Private Windows", targets: privateTargets)
                    destinationSection("Web Apps", targets: pwaTargets)
                    destinationSection("Other Link-Opening Apps", targets: otherApplicationTargets)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
    }

    @ViewBuilder
    private func destinationSection(_ title: String, targets: [RouteTarget]) -> some View {
        if !targets.isEmpty {
            Section(title) {
                ForEach(targets) { target in
                    HStack(spacing: 12) {
                        Image(nsImage: browserCatalog.icon(for: target))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.displayName)
                                .lineLimit(1)
                            Text(BrowserDestinationPresentation.detail(for: target))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Add") { onAdd(target) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var availableTargets: [RouteTarget] {
        browserTargets + profileTargets + privateTargets + pwaTargets + otherApplicationTargets
    }

    private var browserTargets: [RouteTarget] {
        filteredAvailableTargets(
            browserCatalog.browsers
                .filter { BrowserFamilyCatalog.isRecognizedBrowser($0.bundleIdentifier) }
                .map(\.routeTarget)
        )
    }

    private var otherApplicationTargets: [RouteTarget] {
        filteredAvailableTargets(
            browserCatalog.browsers
                .filter { !BrowserFamilyCatalog.isRecognizedBrowser($0.bundleIdentifier) }
                .map(\.routeTarget)
        )
    }

    private var profileTargets: [RouteTarget] {
        filteredAvailableTargets(browserCatalog.profiles.map(\.routeTarget))
    }

    private var privateTargets: [RouteTarget] {
        filteredAvailableTargets(browserCatalog.privateTargets)
    }

    private var pwaTargets: [RouteTarget] {
        filteredAvailableTargets(browserCatalog.pwas.map(\.routeTarget))
    }

    private func filteredAvailableTargets(_ targets: [RouteTarget]) -> [RouteTarget] {
        targets.filter { target in
            !isVisible(target)
                && (searchText.isEmpty
                    || target.displayName.localizedCaseInsensitiveContains(searchText))
        }
    }

    private func isVisible(_ target: RouteTarget) -> Bool {
        BrowserPresentationOrganizer.presentation(
            for: target,
            presentations: settingsStore.settings.linkRouter.browserPresentation,
            defaultsToVisible: browserCatalog.isSuggestedPickerTarget
        ).isShownInPrompt
    }
}

private enum BrowserDestinationPresentation {
    static func detail(for target: RouteTarget) -> String {
        if target.openMode == .privateWindow {
            return "Private window"
        }
        switch target.kind {
        case .browserProfile:
            return "Browser profile"
        case .browserPWA:
            return "Web app"
        case .application:
            guard let bundleIdentifier = target.bundleIdentifier else { return "Application" }
            return BrowserFamilyCatalog.isRecognizedBrowser(bundleIdentifier)
                ? "Browser"
                : "App registered with macOS to open web links"
        default:
            return "Link destination"
        }
    }
}
