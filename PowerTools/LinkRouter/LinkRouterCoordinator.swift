import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class LinkRouterCoordinator {
    private struct ExpansionResult: Sendable {
        let url: URL
        let errorMessage: String?
    }

    private unowned let settingsStore: SettingsStore
    private unowned let browserCatalog: BrowserCatalog
    private unowned let launcher: BrowserLauncher
    private unowned let historyStore: HistoryStore
    private unowned let logger: RoutingLogger
    private unowned let promptController: BrowserPromptController

    private let ruleEngine = RuleEngine()
    private let safeRuleEvaluator = SafeRuleEvaluator()
    private let nativeAppCatalog = NativeAppCatalog()
    private let shortURLResolver = ShortURLResolver()
    private let javaScriptTransformer = JavaScriptURLTransformer()
    private let routingGate = AsyncGate()
    private var cachedRules: [LinkRule] = []
    private var cachedOrderedRules: [LinkRule] = []

    init(
        settingsStore: SettingsStore,
        browserCatalog: BrowserCatalog,
        launcher: BrowserLauncher,
        historyStore: HistoryStore,
        logger: RoutingLogger,
        promptController: BrowserPromptController
    ) {
        self.settingsStore = settingsStore
        self.browserCatalog = browserCatalog
        self.launcher = launcher
        self.historyStore = historyStore
        self.logger = logger
        self.promptController = promptController
    }

    func handleIncoming(_ urls: [URL], trigger: RouterTrigger = .systemLink) {
        let source = SourceAppResolver.shared.resolve()
        Task {
            await settingsStore.loadIfNeeded()
            let settings = settingsStore.settings.linkRouter
            logger.isEnabled = settings.logLevel != .off
            if !settings.isEnabled {
                logger.log(
                    .warning, stage: "Router",
                    "Routing rules and App Links are paused; forwarding URLs to the configured primary target.")
                let request = RouteRequest(
                    urls: urls,
                    sourceApplication: source,
                    trigger: trigger,
                    forcedTarget: settings.primaryTarget,
                    bypassRules: true
                )
                await route(request)
            } else {
                let request = RouteRequest(urls: urls, sourceApplication: source, trigger: trigger)
                await route(request)
            }
        }
    }

    func handleCustomScheme(_ url: URL) {
        Task {
            do {
                await settingsStore.loadIfNeeded()
                if browserCatalog.browsers.isEmpty { await browserCatalog.refresh() }
                let command = try CustomURLCommand(url: url, browserCatalog: browserCatalog)
                switch command.action {
                case .open(let request):
                    var request = request
                    request.sourceApplication = SourceAppResolver.shared.resolve()
                    await route(request)
                case .cleanAndCopy(let url):
                    copySanitizedURL(url)
                case .showSettings:
                    WindowPresenter.shared.showSettings()
                case .showHistory:
                    WindowPresenter.shared.showHistory()
                }
            } catch {
                present(error)
            }
        }
    }

    func route(_ incomingRequest: RouteRequest) async {
        await settingsStore.loadIfNeeded()
        await routingGate.enter()
        await performRoute(incomingRequest)
        await routingGate.leave()
    }

    private func performRoute(_ incomingRequest: RouteRequest) async {
        if browserCatalog.browsers.isEmpty { await browserCatalog.refresh() }
        var request = incomingRequest
        let settings = settingsStore.settings.linkRouter
        logger.isEnabled = settings.logLevel != .off
        launcher.safariPrivateUsesAccessibility = settings.safariPrivateUsesAccessibility
        let modifiers = NSEvent.modifierFlags

        if applyBrowserPickerModifier(
            settings.browserPickerModifier,
            eventModifiers: modifiers,
            to: &request
        ) {
            logger.log(stage: "Input", "Browser-picker modifier was held; user rules are bypassed.")
        }
        if settings.openInBackgroundWhenControlHeld, modifiers.contains(.control) {
            request.openInBackground = true
        }
        if request.trigger == .browserExtension, settings.browserExtensionAlwaysPrompts {
            request.forcePrompt = true
        }

        let expansions = await expandShortURLs(request.urls, settings: settings)
        let preparedRules = request.bypassRules ? [] : await orderedRules(for: settings.rules)
        for (originalURL, expansion) in zip(request.urls, expansions) {
            do {
                try await routeSingle(
                    originalURL,
                    expansion: expansion,
                    request: request,
                    settings: settings,
                    orderedRules: preparedRules
                )
            } catch {
                logger.log(.error, stage: "Router", error.localizedDescription)
                present(error)
            }
        }
    }

    func copySanitizedURL(_ url: URL) {
        let settings = settingsStore.settings.linkRouter
        let sanitizer = makeSanitizer(settings)
        let clean = sanitizer.sanitize(url).url
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clean.absoluteString, forType: .string)
        logger.log(stage: "Clipboard", "Copied sanitized URL: \(clean.absoluteString)")
    }

    private func routeSingle(
        _ originalURL: URL,
        expansion: ExpansionResult,
        request: RouteRequest,
        settings: LinkRouterSettings,
        orderedRules: [LinkRule]
    ) async throws {
        var trace: [RoutingTraceStep] = [
            RoutingTraceStep(stage: "Input", message: "Received \(originalURL.absoluteString)")
        ]
        guard originalURL.absoluteString.utf8.count <= 16_384,
            let scheme = originalURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw CocoaError(
                .fileReadUnsupportedScheme,
                userInfo: [
                    NSLocalizedDescriptionKey: "Only HTTP and HTTPS links can be routed."
                ])
        }

        var workingURL = expansion.url
        if workingURL != originalURL {
            trace.append(RoutingTraceStep(stage: "Redirect", message: "Expanded to \(workingURL.absoluteString)"))
        } else if let errorMessage = expansion.errorMessage {
            trace.append(RoutingTraceStep(stage: "Redirect", message: "Expansion skipped: \(errorMessage)"))
        }

        if settings.removeTrackingParameters || settings.unwrapEmbeddedRedirects {
            let result = makeSanitizer(settings).sanitize(workingURL)
            if !result.unwrappedRedirects.isEmpty {
                trace.append(
                    RoutingTraceStep(
                        stage: "Redirect", message: "Unwrapped \(result.unwrappedRedirects.count) embedded redirect(s)."
                    ))
            }
            if !result.removedQueryItems.isEmpty {
                trace.append(
                    RoutingTraceStep(
                        stage: "Privacy", message: "Removed: \(result.removedQueryItems.joined(separator: ", "))"))
            }
            workingURL = result.url
        }

        var matchedRule: LinkRule?
        var target: RouteTarget?
        var openInNewWindow = request.openInNewWindow
        var openInBackground = request.openInBackground

        if let forced = request.forcedTarget {
            target = forced
            trace.append(RoutingTraceStep(stage: "Target", message: "Forced target: \(forced.displayName)"))
        } else if request.forcePrompt {
            target = .prompt
        } else if !request.bypassRules {
            let match: RuleMatch?
            do {
                match = try await safeRuleEvaluator.firstMatch(
                    for: workingURL,
                    sourceApplication: request.sourceApplication,
                    orderedRules: orderedRules
                )
            } catch {
                match = nil
                trace.append(
                    RoutingTraceStep(
                        stage: "Rule",
                        message: "Unsafe or invalid rule evaluation was skipped: \(error.localizedDescription)"
                    ))
                logger.log(.warning, stage: "Rule", error.localizedDescription)
            }

            if let match {
                matchedRule = match.rule
                target = match.target
                openInNewWindow = openInNewWindow || match.rule.openInNewWindow
                openInBackground = openInBackground || match.rule.openInBackground
                trace.append(RoutingTraceStep(stage: "Rule", message: "Matched “\(match.rule.name)”."))

                if let actions = match.rule.rewriteActions, !actions.isEmpty {
                    do {
                        let transformed = try StructuredURLRewriter().rewrite(workingURL, actions: actions)
                        if transformed != workingURL {
                            trace.append(
                                RoutingTraceStep(
                                    stage: "Rewrite",
                                    message: "Changed the URL to \(transformed.absoluteString)"
                                ))
                            workingURL = transformed
                        }
                    } catch {
                        trace.append(
                            RoutingTraceStep(
                                stage: "Rewrite",
                                message: "Structured rewrite was skipped: \(error.localizedDescription)"
                            ))
                        logger.log(.warning, stage: "Rewrite", error.localizedDescription)
                    }
                }

                if let script = match.rule.transformJavaScript?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !script.isEmpty
                {
                    do {
                        let transformed = try await javaScriptTransformer.transform(
                            url: workingURL,
                            sourceApplication: request.sourceApplication,
                            script: script
                        )
                        trace.append(
                            RoutingTraceStep(
                                stage: "Transform",
                                message: "JavaScript changed the URL to \(transformed.absoluteString)"
                            ))
                        workingURL = transformed
                    } catch {
                        trace.append(
                            RoutingTraceStep(
                                stage: "Transform",
                                message: "JavaScript transform was skipped: \(error.localizedDescription)"
                            ))
                        logger.log(.warning, stage: "Transform", error.localizedDescription)
                    }
                }
            }
        }

        if target == nil,
            let webServiceTarget = webServiceTarget(for: workingURL, settings: settings)
        {
            target = webServiceTarget.target
            trace.append(RoutingTraceStep(stage: "Web Service", message: webServiceTarget.message))
        }

        if target == nil, settings.useNativeAppRouting,
            let native = nativeAppTarget(for: workingURL, enabledIDs: settings.enabledNativeAppIDs)
        {
            target = native.target
            workingURL = native.url
            trace.append(RoutingTraceStep(stage: "Native App", message: "Matched \(native.definition.displayName)."))
        }

        if target == nil {
            target = .primary
        }

        target = resolveSpecialTarget(target ?? .prompt, settings: settings)

        if target?.kind == .prompt {
            let selection = await promptController.choose(
                url: workingURL,
                targets: promptTargets(settings: settings),
                presentation: settings.browserPresentation,
                showsURL: settings.promptShowsURL,
                allowActions: settings.optionRevealsPromptActions,
                controlOpensInBackground: settings.openInBackgroundWhenControlHeld,
                preservePosition: settings.preservePromptPosition
            )
            guard let selection else {
                logger.log(stage: "Prompt", "Browser prompt was dismissed.")
                return
            }
            target = selection.target
            openInBackground = openInBackground || selection.openInBackground
            openInNewWindow = openInNewWindow || selection.openInNewWindow
            if selection.createDomainRule {
                createDomainRule(for: workingURL, target: selection.target)
            }
        }

        guard let finalTarget = target else { return }
        trace.append(RoutingTraceStep(stage: "Target", message: "Selected \(finalTarget.displayName)."))

        switch finalTarget.kind {
        case .copyURL:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(workingURL.absoluteString, forType: .string)
        case .share:
            SharePresenter.shared.present(items: [workingURL])
        case .discard:
            break
        default:
            try await launcher.open(
                urls: [workingURL],
                target: finalTarget,
                inBackground: openInBackground,
                newWindow: openInNewWindow
            )
        }

        logger.log(stage: "Complete", "\(workingURL.absoluteString) → \(finalTarget.displayName)")
        if settings.logLevel == .verbose {
            for step in trace { logger.log(.debug, stage: step.stage, step.message) }
        }
        if settings.historyEnabled {
            await historyStore.append(
                LinkHistoryEntry(
                    originalURL: originalURL,
                    finalURL: workingURL,
                    sourceApplication: request.sourceApplication,
                    target: finalTarget,
                    matchedRuleName: matchedRule?.name,
                    trigger: request.trigger
                ),
                limit: settings.historyLimit
            )
        }
    }

    private func makeSanitizer(_ settings: LinkRouterSettings) -> URLSanitizer {
        URLSanitizer(
            additionalParameters: Set(settings.additionalTrackingParameters),
            allowedParameters: Set(settings.allowedTrackingParameters),
            removeTrackingParameters: settings.removeTrackingParameters,
            unwrapRedirects: settings.unwrapEmbeddedRedirects
        )
    }

    private func orderedRules(for rules: [LinkRule]) async -> [LinkRule] {
        guard cachedRules != rules else { return cachedOrderedRules }
        let ordered = await Task.detached(priority: .userInitiated) { [ruleEngine] in
            ruleEngine.ordered(rules)
        }.value
        cachedRules = rules
        cachedOrderedRules = ordered
        return ordered
    }

    private func expandShortURLs(
        _ urls: [URL],
        settings: LinkRouterSettings
    ) async -> [ExpansionResult] {
        guard settings.expandShortURLs, !urls.isEmpty else {
            return urls.map { ExpansionResult(url: $0, errorMessage: nil) }
        }

        let customHosts = Set(settings.customShortenerHosts)
        let resolveUnknown = settings.resolveUnknownRedirects
        let concurrencyLimit = min(4, urls.count)
        var results = Array<ExpansionResult?>(repeating: nil, count: urls.count)

        await withTaskGroup(of: (Int, ExpansionResult).self) { group in
            var nextIndex = 0
            for _ in 0..<concurrencyLimit {
                let index = nextIndex
                nextIndex += 1
                let url = urls[index]
                group.addTask { [shortURLResolver] in
                    do {
                        let expanded = try await shortURLResolver.resolve(
                            url,
                            customShortenerHosts: customHosts,
                            resolveUnknownRedirects: resolveUnknown
                        )
                        return (index, ExpansionResult(url: expanded, errorMessage: nil))
                    } catch {
                        return (index, ExpansionResult(url: url, errorMessage: error.localizedDescription))
                    }
                }
            }

            while let (completedIndex, result) = await group.next() {
                results[completedIndex] = result
                guard nextIndex < urls.count else { continue }
                let index = nextIndex
                nextIndex += 1
                let url = urls[index]
                group.addTask { [shortURLResolver] in
                    do {
                        let expanded = try await shortURLResolver.resolve(
                            url,
                            customShortenerHosts: customHosts,
                            resolveUnknownRedirects: resolveUnknown
                        )
                        return (index, ExpansionResult(url: expanded, errorMessage: nil))
                    } catch {
                        return (index, ExpansionResult(url: url, errorMessage: error.localizedDescription))
                    }
                }
            }
        }

        return zip(urls, results).map { original, result in
            result ?? ExpansionResult(url: original, errorMessage: "Expansion was cancelled.")
        }
    }

    private func resolveSpecialTarget(_ input: RouteTarget, settings: LinkRouterSettings) -> RouteTarget {
        var current = input
        var visitedKinds: Set<RouteTargetKind> = []

        while [.primaryBrowser, .alternativeBrowser, .systemDefault].contains(current.kind) {
            guard visitedKinds.insert(current.kind).inserted else { return .prompt }
            switch current.kind {
            case .primaryBrowser:
                if let focusTarget = FocusRouteOverride.target(in: browserCatalog) { return focusTarget }
                current = settings.primaryTarget
            case .alternativeBrowser:
                current = settings.alternativeTarget
            case .systemDefault:
                // Power Tools is normally the system default. Calling it again would recurse.
                current = settings.primaryTarget
            default:
                break
            }
        }
        return current
    }

    private func promptTargets(settings: LinkRouterSettings) -> [RouteTarget] {
        let discovered = browserCatalog.allTargets
        let presentationByID = settings.browserPresentation.reduce(into: [String: BrowserPresentation]()) {
            result, presentation in
            result[presentation.id] = presentation
        }
        let visible = discovered.filter {
            presentationByID[$0.id]?.isShownInPrompt ?? browserCatalog.isSuggestedPickerTarget($0)
        }
        let sorted = visible.sorted {
            let lhs = presentationByID[$0.id]?.order ?? Int.max
            let rhs = presentationByID[$1.id]?.order ?? Int.max
            if lhs == rhs { return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            return lhs < rhs
        }
        return sorted.isEmpty ? [.copyURL] : sorted
    }

    private func webServiceTarget(
        for url: URL,
        settings: LinkRouterSettings
    ) -> (target: RouteTarget, message: String)? {
        guard let host = url.host?.lowercased() else { return nil }

        if settings.googleMeetRoutingEnabled,
            host == "meet.google.com" || host.hasSuffix(".meet.google.com")
        {
            if let configured = settings.googleMeetTarget,
                let resolved = browserCatalog.target(withID: configured.id)
                    ?? configured.applicationPath.map({ _ in configured })
            {
                return (resolved, "Google Meet routed to \(resolved.displayName).")
            }
            if let chromium = automaticChromiumTarget() {
                return (chromium, "Google Meet routed to Chromium-compatible browser \(chromium.displayName).")
            }
        }

        let isYouTube =
            host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
        if settings.youtubeRoutingEnabled, isYouTube,
            let configured = settings.youtubeTarget,
            let resolved = browserCatalog.target(withID: configured.id)
                ?? configured.applicationPath.map({ _ in configured })
        {
            return (resolved, "YouTube routed to \(resolved.displayName).")
        }

        return nil
    }

    private func automaticChromiumTarget() -> RouteTarget? {
        let preferredBundleIdentifiers = [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.google.Chrome.dev",
            "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
            "ai.perplexity.comet", "net.imput.helium", "org.chromium.Thorium", "com.bookry.wavebox",
        ]
        for bundleIdentifier in preferredBundleIdentifiers {
            if let browser = browserCatalog.browsers.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return browser.routeTarget
            }
        }
        return nil
    }

    private func nativeAppTarget(
        for url: URL,
        enabledIDs: Set<String>
    ) -> (definition: NativeAppDefinition, target: RouteTarget, url: URL)? {
        guard let definition = nativeAppCatalog.match(url: url, enabledIDs: enabledIDs),
            let transformed = definition.transformedURL(from: url)
        else { return nil }

        for bundleIdentifier in definition.candidateBundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let target = RouteTarget(
                    id: "native.\(definition.id).\(bundleIdentifier)",
                    kind: .application,
                    displayName: definition.displayName,
                    bundleIdentifier: bundleIdentifier,
                    applicationPath: appURL.path
                )
                return (definition, target, transformed)
            }
        }

        if transformed.scheme != url.scheme,
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: transformed),
            let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        {
            let target = RouteTarget(
                id: "native.\(definition.id).\(bundleIdentifier)",
                kind: .application,
                displayName: definition.displayName,
                bundleIdentifier: bundleIdentifier,
                applicationPath: appURL.path
            )
            return (definition, target, transformed)
        }
        return nil
    }

    private func createDomainRule(for url: URL, target: RouteTarget) {
        guard let host = url.host else { return }
        let nextPriority = (settingsStore.settings.linkRouter.rules.map(\.priority).max() ?? 0) + 1
        let rule = LinkRule(
            name: "Open \(host) in \(target.displayName)",
            priority: nextPriority,
            urlMatchers: [URLMatcher(kind: .hostSuffix, pattern: host)],
            target: target
        )
        settingsStore.settings.linkRouter.rules.append(rule)
        logger.log(stage: "Rule", "Created a domain rule for \(host).")
    }

    private func present(_ error: Error) {
        logger.log(.error, stage: "Error", error.localizedDescription)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

@discardableResult
func applyBrowserPickerModifier(
    _ modifier: BrowserPickerModifier,
    eventModifiers: NSEvent.ModifierFlags,
    to request: inout RouteRequest
) -> Bool {
    let isHeld =
        switch modifier {
        case .function: eventModifiers.contains(.function)
        case .option: eventModifiers.contains(.option)
        case .control: eventModifiers.contains(.control)
        case .shift: eventModifiers.contains(.shift)
        case .command: eventModifiers.contains(.command)
        case .disabled: false
        }
    guard isHeld else { return false }

    request.forcedTarget = nil
    request.forcePrompt = true
    request.bypassRules = true
    return true
}
