import AppKit
import LinkRouterCore
import SwiftUI
import UniformTypeIdentifiers

struct RulesSettingsView: View {
    @State private var presentationMode: RulesPresentationMode = .automations

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            HStack(alignment: .center, spacing: 20) {
                SettingsPageHeader(
                    title: "Rules & Exceptions",
                    subtitle: "Create simple automations or use advanced conditions for precise routing."
                )

                Picker("Rules view", selection: $presentationMode) {
                    ForEach(RulesPresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }

            Group {
                switch presentationMode {
                case .automations:
                    AutomationRulesView { presentationMode = .advanced }
                case .advanced:
                    AdvancedRulesSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum RulesPresentationMode: String, CaseIterable, Identifiable {
    case automations
    case advanced

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automations: "Automations"
        case .advanced: "Advanced Rules"
        }
    }
}

private struct AdvancedRulesSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selectedRuleID: UUID?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced Rules").font(.headline)
                    Text("Condition groups, URL rewrites, JavaScript, and exact priority.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: addRule) { Label("Add", systemImage: "plus") }
                Button(action: duplicateRule) { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .disabled(selectedRuleID == nil)
                Button(role: .destructive, action: deleteRule) { Label("Delete", systemImage: "trash") }
                    .disabled(selectedRuleID == nil)
                Menu("Import / Export") {
                    Button("Import Rules…", action: importRules)
                    Button("Export Rules…", action: exportRules)
                }
            }

            if settingsStore.settings.linkRouter.rules.isEmpty {
                ContentUnavailableView(
                    "No Advanced Rules",
                    systemImage: "arrow.triangle.branch",
                    description: Text(
                        "Use Add to build a rule from individual conditions and actions, or switch to Automations for a guided setup."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedRuleID) {
                        ForEach(settingsStore.settings.linkRouter.rules.sorted(by: ruleSort)) { rule in
                            HStack {
                                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(rule.isEnabled ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.name)
                                    Text("Priority \(rule.priority) · \(rule.target.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(rule.id)
                        }
                    }
                    .frame(minWidth: 235, idealWidth: 260, maxWidth: 320)

                    if let selectedRuleID, let binding = ruleBinding(id: selectedRuleID) {
                        RuleEditorView(rule: binding)
                            .id(selectedRuleID)
                            .frame(minWidth: 430)
                    } else {
                        ContentUnavailableView(
                            "Select a Rule",
                            systemImage: "arrow.triangle.branch",
                            description: Text("Select a rule from the list to edit its behavior.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func ruleSort(_ lhs: LinkRule, _ rhs: LinkRule) -> Bool {
        if lhs.priority == rhs.priority { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        return lhs.priority > rhs.priority
    }

    private func ruleBinding(id: UUID) -> Binding<LinkRule>? {
        guard settingsStore.settings.linkRouter.rules.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                settingsStore.settings.linkRouter.rules.first(where: { $0.id == id })
                    ?? LinkRule(name: "Unavailable Rule", isEnabled: false, target: .discard)
            },
            set: { updated in
                guard let index = settingsStore.settings.linkRouter.rules.firstIndex(where: { $0.id == id }) else {
                    return
                }
                var copy = updated
                copy.updatedAt = Date()
                settingsStore.settings.linkRouter.rules[index] = copy
            }
        )
    }

    private func addRule() {
        let nextPriority = (settingsStore.settings.linkRouter.rules.map(\.priority).max() ?? 0) + 10
        let rule = LinkRule(
            name: "New Rule",
            priority: nextPriority,
            urlMatcherGroups: [
                URLMatcherGroup(
                    mode: .any,
                    matchers: [URLMatcher(kind: .hostSuffix, pattern: "example.com")]
                )
            ],
            target: .primary,
            editorKind: .advanced
        )
        settingsStore.settings.linkRouter.rules.append(rule)
        selectedRuleID = rule.id
    }

    private func duplicateRule() {
        guard let selectedRuleID,
            var rule = settingsStore.settings.linkRouter.rules.first(where: { $0.id == selectedRuleID })
        else { return }
        rule.id = UUID()
        rule.name += " Copy"
        rule.createdAt = Date()
        rule.updatedAt = Date()
        settingsStore.settings.linkRouter.rules.append(rule)
        self.selectedRuleID = rule.id
    }

    private func deleteRule() {
        guard let selectedRuleID else { return }
        settingsStore.settings.linkRouter.rules.removeAll { $0.id == selectedRuleID }
        self.selectedRuleID = nil
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await settingsStore.importRules(from: url, replacingExisting: false) } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PotliJi-Rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await settingsStore.exportRules(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }
}

private struct RuleEditorView: View {
    @EnvironmentObject private var browserCatalog: BrowserCatalog
    @Binding var rule: LinkRule
    @State private var sampleURL = "https://example.com/path"
    @State private var sampleSourceBundleID = ""
    @State private var sampleResult: Bool?
    @State private var sampleFinalURL: URL?
    @State private var sampleError: String?

    var body: some View {
        ScrollView {
            Form {
                Section("Rule") {
                    TextField("Name", text: $rule.name)
                    Toggle("Enabled", isOn: $rule.isEnabled)
                    Stepper("Priority: \(rule.priority)", value: $rule.priority, in: -10_000...10_000)
                    TextField("Notes", text: $rule.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Open In") {
                    Picker("Destination", selection: $rule.target) {
                        Text(RouteTarget.primary.displayName).tag(RouteTarget.primary)
                        Text(RouteTarget.prompt.displayName).tag(RouteTarget.prompt)
                        Text(RouteTarget.copyURL.displayName).tag(RouteTarget.copyURL)
                        Text(RouteTarget.share.displayName).tag(RouteTarget.share)
                        Divider()
                        if rule.target.kind == .application,
                            !browserCatalog.allTargets.contains(where: { $0.id == rule.target.id })
                        {
                            Text(rule.target.displayName).tag(rule.target)
                            Divider()
                        }
                        ForEach(browserCatalog.allTargets) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    HStack {
                        Button("Choose Any Application…") { chooseDestinationApplication() }
                        if rule.target.kind == .application {
                            Text(rule.target.applicationPath ?? rule.target.bundleIdentifier ?? rule.target.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Toggle("Force a new window", isOn: $rule.openInNewWindow)
                    Toggle("Open in background", isOn: $rule.openInBackground)
                }

                Section("Link Conditions") {
                    Text(
                        "Every group must match. Use Match Any for aliases such as x.com or twitter.com, and Match All when several requirements must be true."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if matcherGroups.isEmpty {
                        Label(
                            "No link conditions — this rule applies to every URL.",
                            systemImage: "globe"
                        )
                        .foregroundStyle(.secondary)
                    }
                    ForEach(Array(matcherGroups.enumerated()), id: \.element.id) { index, group in
                        if let binding = matcherGroupBinding(group.id) {
                            URLMatcherGroupEditor(
                                title: "Condition Group \(index + 1)",
                                group: binding
                            ) {
                                rule.urlMatcherGroups?.removeAll { $0.id == group.id }
                            }
                        }
                    }
                    Button {
                        if rule.urlMatcherGroups == nil { rule.urlMatcherGroups = [] }
                        rule.urlMatcherGroups?.append(
                            URLMatcherGroup(
                                mode: .any,
                                matchers: [URLMatcher(kind: .hostSuffix, pattern: "example.com")]
                            ))
                    } label: {
                        Label("Add Condition Group", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                Section("Source Applications") {
                    if rule.sourceAppMatchers.isEmpty {
                        Text("No source application means links from every app can match.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(rule.sourceAppMatchers.indices), id: \.self) { index in
                        SourceApplicationMatcherRow(
                            title: "Application \(index + 1)",
                            matcher: $rule.sourceAppMatchers[index],
                            chooseApplication: { chooseSourceApplication(at: index) },
                            delete: {
                                rule.sourceAppMatchers.remove(at: index)
                            }
                        )
                    }
                    Button {
                        rule.sourceAppMatchers.append(SourceAppMatcher(bundleIdentifier: ""))
                    } label: {
                        Label("Add Source App", systemImage: "plus")
                    }
                    Text(
                        "Multiple included applications work as alternatives. An excluded application always blocks the rule."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Structured URL Rewrites") {
                    if rewriteActions.isEmpty {
                        Text("No structured rewrite actions.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(rewriteActions.enumerated()), id: \.element.id) { index, action in
                        if let binding = rewriteActionBinding(action.id) {
                            URLRewriteActionRow(
                                title: "Action \(index + 1)",
                                action: binding
                            ) {
                                rule.rewriteActions?.removeAll { $0.id == action.id }
                            }
                        }
                    }
                    Menu {
                        ForEach(URLRewriteKind.allCases, id: \.self) { kind in
                            Button(rewriteLabel(kind)) {
                                if rule.rewriteActions == nil { rule.rewriteActions = [] }
                                rule.rewriteActions?.append(URLRewriteAction(kind: kind))
                            }
                        }
                    } label: {
                        Label("Add Rewrite Action", systemImage: "plus")
                    }
                    Text("Actions run from top to bottom before the JavaScript transform.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Advanced JavaScript Transform") {
                    Text(
                        "The script receives `$` with `$.url` and `$.sourceApp`. Assign a new value to `$.url.href`, or edit pathname/search/hash fields."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextEditor(
                        text: Binding(
                            get: { rule.transformJavaScript ?? "" },
                            set: { rule.transformJavaScript = $0.isEmpty ? nil : $0 }
                        )
                    )
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                }

                Section("Test") {
                    TextField("Sample URL", text: $sampleURL)
                    TextField("Sample source bundle identifier", text: $sampleSourceBundleID)
                    Button("Evaluate Safely") {
                        Task { await evaluateSample() }
                    }
                    if let sampleResult {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: sampleResult ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(sampleResult ? .green : .red)
                                Text(
                                    sampleResult
                                        ? "This rule matches the sample."
                                        : "This rule does not match the sample.")
                            }
                            if let sampleFinalURL {
                                Text("Final link: \(sampleFinalURL.absoluteString)")
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Text("Destination: \(rule.target.displayName)")
                                    .font(.caption)
                            }
                        }
                    } else if let sampleError {
                        Label(sampleError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func chooseDestinationApplication() {
        guard let appURL = chooseApplicationURL() else { return }
        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        rule.target = RouteTarget(
            id: "custom.app.\(bundleIdentifier ?? appURL.lastPathComponent)",
            kind: .application,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            applicationPath: appURL.path
        )
    }

    private var matcherGroups: [URLMatcherGroup] {
        if let groups = rule.urlMatcherGroups { return groups }
        return rule.urlMatchers.isEmpty ? [] : [URLMatcherGroup(mode: .all, matchers: rule.urlMatchers)]
    }

    private var rewriteActions: [URLRewriteAction] {
        rule.rewriteActions ?? []
    }

    private func matcherGroupBinding(_ id: UUID) -> Binding<URLMatcherGroup>? {
        guard matcherGroups.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                matcherGroups.first(where: { $0.id == id })
                    ?? URLMatcherGroup(mode: .any, matchers: [])
            },
            set: { updated in
                if rule.urlMatcherGroups == nil { rule.urlMatcherGroups = matcherGroups }
                guard let index = rule.urlMatcherGroups?.firstIndex(where: { $0.id == id }) else { return }
                rule.urlMatcherGroups?[index] = updated
                rule.urlMatchers = []
            }
        )
    }

    private func rewriteActionBinding(_ id: UUID) -> Binding<URLRewriteAction>? {
        guard rewriteActions.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                rewriteActions.first(where: { $0.id == id })
                    ?? URLRewriteAction(kind: .forceHTTPS)
            },
            set: { updated in
                if rule.rewriteActions == nil { rule.rewriteActions = rewriteActions }
                guard let index = rule.rewriteActions?.firstIndex(where: { $0.id == id }) else { return }
                rule.rewriteActions?[index] = updated
            }
        )
    }

    private func rewriteLabel(_ kind: URLRewriteKind) -> String {
        switch kind {
        case .replaceHost: "Replace Domain"
        case .forceHTTPS: "Force HTTPS"
        case .replacePathPrefix: "Replace Path Prefix"
        case .removeQueryParameters: "Remove Query Parameters"
        case .setQueryParameter: "Set Query Parameter"
        }
    }

    private func chooseSourceApplication(at index: Int) {
        guard rule.sourceAppMatchers.indices.contains(index),
            let appURL = chooseApplicationURL(),
            let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        else { return }
        rule.sourceAppMatchers[index].bundleIdentifier = bundleIdentifier
    }

    private func chooseApplicationURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private func evaluateSample() async {
        guard let url = URL(string: sampleURL),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            sampleResult = nil
            sampleFinalURL = nil
            sampleError = "Enter a valid HTTP or HTTPS URL."
            return
        }
        let source =
            sampleSourceBundleID.isEmpty
            ? nil
            : SourceApplication(bundleIdentifier: sampleSourceBundleID, name: sampleSourceBundleID)
        do {
            let evaluator = SafeRuleEvaluator()
            let preparedRules = try await evaluator.prepare([rule])
            let match = try await evaluator.firstMatch(
                for: url,
                sourceApplication: source,
                preparedRules: preparedRules
            )
            sampleResult = match != nil
            var finalURL: URL?
            if match != nil {
                var transformed = try StructuredURLRewriter().rewrite(
                    url,
                    actions: rule.rewriteActions ?? []
                )
                if let script = rule.transformJavaScript?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !script.isEmpty
                {
                    transformed = try await JavaScriptURLTransformer().transform(
                        url: transformed,
                        sourceApplication: source,
                        script: script
                    )
                }
                finalURL = transformed
            }
            sampleFinalURL = finalURL
            sampleError = nil
        } catch {
            sampleResult = nil
            sampleFinalURL = nil
            sampleError = error.localizedDescription
        }
    }
}
