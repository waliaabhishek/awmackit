import AppKit
import LinkRouterCore
import SwiftUI
import UniformTypeIdentifiers

struct WebsiteFamilyDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let systemImage: String
    let domains: [String]
    let sampleURL: String
}

enum WebsiteFamilyCatalog {
    static let builtIns: [WebsiteFamilyDefinition] = [
        WebsiteFamilyDefinition(
            id: "youtube",
            name: "YouTube",
            description: "Videos, Shorts, Music, and shared youtu.be links",
            systemImage: "play.rectangle.fill",
            domains: ["youtube.com", "youtu.be", "youtube-nocookie.com"],
            sampleURL: "https://youtu.be/dQw4w9WgXcQ"
        ),
        WebsiteFamilyDefinition(
            id: "x-twitter",
            name: "X / Twitter",
            description: "Current x.com and legacy twitter.com links",
            systemImage: "bubble.left.and.bubble.right.fill",
            domains: ["x.com", "twitter.com"],
            sampleURL: "https://x.com/example/status/123"
        ),
        WebsiteFamilyDefinition(
            id: "reddit",
            name: "Reddit",
            description: "Reddit pages and shared redd.it links",
            systemImage: "text.bubble.fill",
            domains: ["reddit.com", "redd.it"],
            sampleURL: "https://www.reddit.com/r/macapps/"
        ),
        WebsiteFamilyDefinition(
            id: "google-workspace",
            name: "Google Workspace",
            description: "Docs, Sheets, Slides, Drive, Calendar, and Gmail",
            systemImage: "square.grid.2x2.fill",
            domains: [
                "docs.google.com", "sheets.google.com", "slides.google.com", "drive.google.com",
                "calendar.google.com", "mail.google.com",
            ],
            sampleURL: "https://docs.google.com/document/d/example"
        ),
        WebsiteFamilyDefinition(
            id: "microsoft-365",
            name: "Microsoft 365",
            description: "Office, Outlook, SharePoint, and Teams web links",
            systemImage: "building.2.fill",
            domains: ["office.com", "microsoft365.com", "outlook.office.com", "sharepoint.com", "teams.microsoft.com"],
            sampleURL: "https://www.office.com/"
        ),
        WebsiteFamilyDefinition(
            id: "meetings",
            name: "Meeting Links",
            description: "Google Meet, Zoom, Microsoft Teams, and Webex",
            systemImage: "video.fill",
            domains: ["meet.google.com", "zoom.us", "teams.microsoft.com", "webex.com"],
            sampleURL: "https://meet.google.com/abc-defg-hij"
        ),
    ]

    static func family(id: String?) -> WebsiteFamilyDefinition? {
        guard let id else { return nil }
        return builtIns.first { $0.id == id }
    }
}

enum AutomationRecipe: String, CaseIterable, Identifiable {
    case websiteBrowser
    case privacyFrontend
    case sourceApplication
    case websitePicker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .websiteBrowser: "Open Websites in a Browser"
        case .privacyFrontend: "Use a Privacy Frontend"
        case .sourceApplication: "Route Links from an App"
        case .websitePicker: "Always Ask for Websites"
        }
    }

    var detail: String {
        switch self {
        case .websiteBrowser: "Choose a website family and the browser or profile that should open it."
        case .privacyFrontend: "Rewrite a website to another domain before opening it."
        case .sourceApplication: "Send links clicked in an application to a chosen browser or profile."
        case .websitePicker: "Show the full browser picker for selected websites."
        }
    }

    var systemImage: String {
        switch self {
        case .websiteBrowser: "safari.fill"
        case .privacyFrontend: "hand.raised.fill"
        case .sourceApplication: "arrow.up.forward.app.fill"
        case .websitePicker: "rectangle.stack.fill"
        }
    }
}

struct AutomationRulesView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var editingContext: AutomationEditingContext?
    @State private var rulePendingDeletion: LinkRule?

    let showAdvancedEditor: () -> Void

    private var orderedRules: [LinkRule] {
        RuleEngine().ordered(settingsStore.settings.linkRouter.rules)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Automations")
                        .font(.headline)
                    Text("Create useful link behavior without writing patterns or scripts.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                recipeMenu
            }

            if orderedRules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(Array(orderedRules.enumerated()), id: \.element.id) { index, rule in
                        AutomationRuleRow(
                            rule: rule,
                            isEnabled: enabledBinding(rule.id),
                            edit: { edit(rule) },
                            duplicate: { duplicate(rule) },
                            delete: { rulePendingDeletion = rule },
                            moveUp: { move(rule, by: -1) },
                            moveDown: { move(rule, by: 1) },
                            canMoveUp: index > 0,
                            canMoveDown: index + 1 < orderedRules.count,
                            showAdvanced: showAdvancedEditor
                        )
                    }
                }
                .listStyle(.inset)

                HStack {
                    Label(
                        "Automations are checked from top to bottom. The first match chooses the destination.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Advanced Rules", action: showAdvancedEditor)
                }
            }
        }
        .sheet(item: $editingContext) { context in
            GuidedAutomationEditor(rule: context.rule) { savedRule in
                save(savedRule, replacing: context.replacedRuleID)
            }
            .environmentObject(settingsStore)
        }
        .alert(
            "Delete Automation?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ),
            presenting: rulePendingDeletion
        ) { rule in
            Button("Delete", role: .destructive) { delete(rule) }
            Button("Cancel", role: .cancel) {}
        } message: { rule in
            Text("“\(rule.name)” will be removed. This cannot be undone.")
        }
    }

    private var recipeMenu: some View {
        Menu {
            ForEach(AutomationRecipe.allCases) { recipe in
                Button {
                    create(recipe)
                } label: {
                    Label(recipe.title, systemImage: recipe.systemImage)
                }
            }
        } label: {
            Label("Add Automation", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                "Make Links Work Your Way",
                systemImage: "wand.and.stars",
                description: Text("Start with a recipe. You can review the exact behavior before saving it.")
            )
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AutomationRecipe.allCases) { recipe in
                    Button {
                        create(recipe)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: recipe.systemImage)
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title).font(.headline)
                                Text(recipe.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func create(_ recipe: AutomationRecipe) {
        let nextPriority = (settingsStore.settings.linkRouter.rules.map(\.priority).max() ?? 0) + 10
        editingContext = AutomationEditingContext(
            rule: Self.initialRule(for: recipe, priority: nextPriority),
            replacedRuleID: nil
        )
    }

    private func edit(_ rule: LinkRule) {
        guard rule.editorKind == .guided else {
            showAdvancedEditor()
            return
        }
        editingContext = AutomationEditingContext(rule: rule, replacedRuleID: rule.id)
    }

    private func save(_ rule: LinkRule, replacing id: UUID?) {
        if let id, let index = settingsStore.settings.linkRouter.rules.firstIndex(where: { $0.id == id }) {
            settingsStore.settings.linkRouter.rules[index] = rule
        } else {
            settingsStore.settings.linkRouter.rules.append(rule)
        }
    }

    private func duplicate(_ rule: LinkRule) {
        var copy = rule
        copy.id = UUID()
        copy.name += " Copy"
        copy.priority = (settingsStore.settings.linkRouter.rules.map(\.priority).max() ?? 0) + 10
        copy.createdAt = Date()
        copy.updatedAt = Date()
        settingsStore.settings.linkRouter.rules.append(copy)
    }

    private func delete(_ rule: LinkRule) {
        settingsStore.settings.linkRouter.rules.removeAll { $0.id == rule.id }
        rulePendingDeletion = nil
    }

    private func move(_ rule: LinkRule, by offset: Int) {
        var rules = orderedRules
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let destination = index + offset
        guard rules.indices.contains(destination) else { return }
        rules.swapAt(index, destination)
        for (position, ruleIndex) in rules.indices.enumerated() {
            rules[ruleIndex].priority = (rules.count - position) * 10
        }
        settingsStore.settings.linkRouter.rules = rules
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings.linkRouter.rules.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { value in
                guard let index = settingsStore.settings.linkRouter.rules.firstIndex(where: { $0.id == id }) else {
                    return
                }
                settingsStore.settings.linkRouter.rules[index].isEnabled = value
            }
        )
    }

    private static func initialRule(for recipe: AutomationRecipe, priority: Int) -> LinkRule {
        switch recipe {
        case .websiteBrowser:
            return guidedRule(
                name: "Open YouTube in My Browser",
                priority: priority,
                family: WebsiteFamilyCatalog.builtIns[0],
                target: .primary
            )
        case .privacyFrontend:
            return guidedRule(
                name: "Open X through xcancel.com",
                priority: priority,
                family: WebsiteFamilyCatalog.builtIns[1],
                target: .primary,
                rewrites: [URLRewriteAction(kind: .replaceHost, value: "xcancel.com")]
            )
        case .sourceApplication:
            return LinkRule(
                name: "Links from an Application",
                priority: priority,
                urlMatcherGroups: [],
                target: .primary,
                editorKind: .guided,
                websiteFamilyID: GuidedWebsiteScope.custom
            )
        case .websitePicker:
            return guidedRule(
                name: "Ask for YouTube Links",
                priority: priority,
                family: WebsiteFamilyCatalog.builtIns[0],
                target: .prompt
            )
        }
    }

    private static func guidedRule(
        name: String,
        priority: Int,
        family: WebsiteFamilyDefinition,
        target: RouteTarget,
        rewrites: [URLRewriteAction] = []
    ) -> LinkRule {
        LinkRule(
            name: name,
            priority: priority,
            urlMatcherGroups: [
                URLMatcherGroup(
                    mode: .any,
                    matchers: family.domains.map { URLMatcher(kind: .hostSuffix, pattern: $0) }
                )
            ],
            target: target,
            rewriteActions: rewrites,
            editorKind: .guided,
            websiteFamilyID: family.id
        )
    }
}

private struct AutomationEditingContext: Identifiable {
    let id = UUID()
    let rule: LinkRule
    let replacedRuleID: UUID?
}

private struct AutomationRuleRow: View {
    let rule: LinkRule
    @Binding var isEnabled: Bool
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let showAdvanced: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
            Image(
                systemName: family?.systemImage
                    ?? (rule.editorKind == .guided ? "wand.and.stars" : "slider.horizontal.3")
            )
            .font(.title3)
            .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(rule.name).font(.headline)
                    if rule.editorKind != .guided {
                        Text("ADVANCED")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(rule.editorKind == .guided ? "Edit" : "Advanced") {
                rule.editorKind == .guided ? edit() : showAdvanced()
            }
            Menu {
                Button("Duplicate", action: duplicate)
                Divider()
                Button("Move Up", action: moveUp).disabled(!canMoveUp)
                Button("Move Down", action: moveDown).disabled(!canMoveDown)
                Divider()
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .opacity(isEnabled ? 1 : 0.58)
    }

    private var family: WebsiteFamilyDefinition? {
        WebsiteFamilyCatalog.family(id: rule.websiteFamilyID)
    }

    private var summary: String {
        let condition: String
        if let family {
            condition = family.name
        } else if let group = rule.urlMatcherGroups?.first, !group.matchers.isEmpty {
            let domains = group.matchers.map(\.pattern)
            condition = domains.count == 1 ? domains[0] : "\(domains.count) websites"
        } else if let source = rule.sourceAppMatchers.first {
            condition = "links from \(Self.applicationName(bundleIdentifier: source.bundleIdentifier))"
        } else {
            condition = "all links"
        }

        let rewrite =
            (rule.rewriteActions ?? []).first(where: { $0.kind == .replaceHost })
            .map { "rewrite to \($0.value), then " } ?? ""
        return "When: \(condition) → \(rewrite)open in \(rule.target.displayName)"
    }

    private static func applicationName(bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            let bundle = Bundle(url: url)
        else { return bundleIdentifier }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}

private struct GuidedAutomationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var rule: LinkRule
    @State private var sampleURL: String

    let onSave: (LinkRule) -> Void

    init(rule: LinkRule, onSave: @escaping (LinkRule) -> Void) {
        _rule = State(initialValue: rule)
        let sample = WebsiteFamilyCatalog.family(id: rule.websiteFamilyID)?.sampleURL ?? "https://example.com/path"
        _sampleURL = State(initialValue: sample)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name).font(.title2.bold())
                    Text("Describe what should happen. Power Tools builds the rule for you.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                Form {
                    Section("Name") {
                        TextField("Automation name", text: $rule.name)
                    }

                    Section("When") {
                        Picker("Website family", selection: familySelection) {
                            Text("Custom websites").tag(GuidedWebsiteScope.custom)
                            Text("Any website").tag(GuidedWebsiteScope.all)
                            Divider()
                            ForEach(WebsiteFamilyCatalog.builtIns) { family in
                                Label(family.name, systemImage: family.systemImage).tag(family.id)
                            }
                        }
                        if familySelection.wrappedValue == GuidedWebsiteScope.all {
                            Label("Every website can match this automation.", systemImage: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            TextEditor(text: domainsText)
                                .font(.body)
                                .frame(minHeight: 66)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(nsColor: .separatorColor)))
                            Text(
                                "Websites are alternatives: matching any one of them is enough. Enter one domain per line."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("Source application")
                                Spacer()
                                if let source = rule.sourceAppMatchers.first {
                                    Text(applicationName(source.bundleIdentifier))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else {
                                    Text("Any application")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button("Choose Application…", action: chooseSourceApplication)
                                Spacer()
                                if !rule.sourceAppMatchers.isEmpty {
                                    Button("Clear") { rule.sourceAppMatchers = [] }
                                }
                            }
                        }
                    }

                    Section("Change Link") {
                        Toggle("Replace the website before opening", isOn: rewriteEnabled)
                        if rewriteEnabled.wrappedValue {
                            TextField("New domain", text: replacementHost)
                            Text("The path, query parameters, and fragment are preserved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if replacementHost.wrappedValue == "xcancel.com" {
                                Label(
                                    "This sends the link to an independent third-party service. Review its privacy policy before relying on it.",
                                    systemImage: "hand.raised"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        }
                    }

                    Section("Open With") {
                        RouteTargetPicker(title: "Destination", selection: $rule.target)
                    }

                    Section("Preview") {
                        TextField("Try a link", text: $sampleURL)
                        preview
                    }

                    Section("Options") {
                        Toggle("Open in a new window", isOn: $rule.openInNewWindow)
                        Toggle("Open in background", isOn: $rule.openInBackground)
                        TextField("Notes", text: $rule.notes, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save Automation") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 650, idealHeight: 720)
    }

    @ViewBuilder
    private var preview: some View {
        if let url = URL(string: sampleURL),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        {
            let source = rule.sourceAppMatchers.first.map {
                SourceApplication(bundleIdentifier: $0.bundleIdentifier, name: applicationName($0.bundleIdentifier))
            }
            if rule.matches(url: url, sourceApplication: source) {
                if let finalURL = try? StructuredURLRewriter().rewrite(
                    url,
                    actions: rule.rewriteActions ?? []
                ) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("This automation matches", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Final link: \(finalURL.absoluteString)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Text("Destination: \(rule.target.displayName)")
                            .font(.caption)
                    }
                } else {
                    Label(
                        "The replacement domain is not valid.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            } else {
                Label("This automation does not match this link", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Enter a complete http:// or https:// link.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private var familySelection: Binding<String> {
        Binding(
            get: {
                if let id = rule.websiteFamilyID { return id }
                return GuidedWebsiteScope.custom
            },
            set: { value in
                switch value {
                case GuidedWebsiteScope.all:
                    rule.websiteFamilyID = GuidedWebsiteScope.all
                    setDomains([])
                case GuidedWebsiteScope.custom:
                    rule.websiteFamilyID = GuidedWebsiteScope.custom
                default:
                    guard let family = WebsiteFamilyCatalog.family(id: value) else { return }
                    rule.websiteFamilyID = family.id
                    setDomains(family.domains)
                    sampleURL = family.sampleURL
                }
            }
        )
    }

    private var domainsText: Binding<String> {
        Binding(
            get: { domains.joined(separator: "\n") },
            set: { value in
                rule.websiteFamilyID = GuidedWebsiteScope.custom
                setDomains(
                    value
                        .split(whereSeparator: { $0 == "," || $0.isNewline })
                        .map(String.init)
                )
            }
        )
    }

    private var rewriteEnabled: Binding<Bool> {
        Binding(
            get: { !(rule.rewriteActions ?? []).isEmpty },
            set: { enabled in
                if enabled {
                    rule.rewriteActions = [URLRewriteAction(kind: .replaceHost)]
                } else {
                    rule.rewriteActions = []
                }
            }
        )
    }

    private var replacementHost: Binding<String> {
        Binding(
            get: { rule.rewriteActions?.first(where: { $0.kind == .replaceHost })?.value ?? "" },
            set: { value in
                if let index = rule.rewriteActions?.firstIndex(where: { $0.kind == .replaceHost }) {
                    rule.rewriteActions?[index].value = value
                } else {
                    rule.rewriteActions = [URLRewriteAction(kind: .replaceHost, value: value)]
                }
            }
        )
    }

    private var domains: [String] {
        rule.urlMatcherGroups?.first?.matchers.map(\.pattern) ?? []
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give this automation a name."
        }
        let matchesAnyWebsite = rule.websiteFamilyID == GuidedWebsiteScope.all
        if !matchesAnyWebsite && domains.isEmpty && rule.sourceAppMatchers.isEmpty {
            return "Choose at least one website or a source application."
        }
        if rewriteEnabled.wrappedValue && !replacementHostIsValid {
            return "Enter a valid replacement domain, such as example.com."
        }
        return nil
    }

    private var replacementHostIsValid: Bool {
        guard rewriteEnabled.wrappedValue,
            let validationURL = URL(string: "https://example.com/")
        else { return !rewriteEnabled.wrappedValue }
        let action = URLRewriteAction(kind: .replaceHost, value: replacementHost.wrappedValue)
        return
            (try? StructuredURLRewriter().rewrite(
                validationURL,
                actions: [action]
            )) != nil
    }

    private func setDomains(_ values: [String]) {
        let normalized = values.compactMap { raw -> String? in
            let value =
                raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            return value.isEmpty ? nil : value
        }
        rule.urlMatchers = []
        rule.urlMatcherGroups =
            normalized.isEmpty
            ? []
            : [
                URLMatcherGroup(
                    mode: .any,
                    matchers: normalized.map { URLMatcher(kind: .hostSuffix, pattern: $0) }
                )
            ]
    }

    private func chooseSourceApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let appURL = panel.url,
            let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        else { return }
        rule.sourceAppMatchers = [SourceAppMatcher(bundleIdentifier: bundleIdentifier)]
    }

    private func applicationName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            let bundle = Bundle(url: url)
        else { return bundleIdentifier }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    private func save() {
        var saved = rule
        saved.editorKind = .guided
        saved.updatedAt = Date()
        onSave(saved)
        dismiss()
    }
}

private enum GuidedWebsiteScope {
    static let custom = "__custom__"
    static let all = "__all__"
}
