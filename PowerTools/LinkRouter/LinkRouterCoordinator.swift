import AppKit
import Foundation
import LinkRouterCore

@MainActor
final class LinkRouterCoordinator {
    private struct PreparedURL {
        let originalURL: URL
        let workingURL: URL
        let trace: [RoutingTraceStep]
    }

    private unowned let settingsStore: SettingsStore
    private unowned let browserCatalog: BrowserCatalog
    private unowned let launcher: BrowserLauncher
    private unowned let historyStore: HistoryStore
    private unowned let logger: RoutingLogger
    private unowned let promptController: BrowserPromptController

    private let safeRuleEvaluator = SafeRuleEvaluator()
    private let shortURLExpander = ShortURLExpander()
    private let targetResolver: RouteTargetResolver
    private let javaScriptTransformer = JavaScriptURLTransformer()
    private var cachedRules: [LinkRule] = []
    private var cachedPreparedRules = SafeRuleEvaluator.PreparedRules.empty

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
        targetResolver = RouteTargetResolver(browserCatalog: browserCatalog)
    }

    func handleIncoming(_ urls: [URL], trigger: RouterTrigger = .systemLink) {
        let source = SourceAppResolver.shared.resolve()
        let eventModifiers = NSEvent.modifierFlags
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
                await route(request, eventModifiers: eventModifiers)
            } else {
                let request = RouteRequest(urls: urls, sourceApplication: source, trigger: trigger)
                await route(request, eventModifiers: eventModifiers)
            }
        }
    }

    func handleCustomScheme(_ url: URL) {
        let eventModifiers = NSEvent.modifierFlags
        Task {
            do {
                await settingsStore.loadIfNeeded()
                await browserCatalog.loadApplicationsIfNeeded()
                let command = try CustomURLCommand(url: url, browserCatalog: browserCatalog)
                switch command.action {
                case .open(let request):
                    var request = request
                    request.sourceApplication = SourceAppResolver.shared.resolve()
                    await route(request, eventModifiers: eventModifiers)
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

    func route(
        _ incomingRequest: RouteRequest,
        eventModifiers: NSEvent.ModifierFlags = []
    ) async {
        await settingsStore.loadIfNeeded()
        await performRoute(incomingRequest, eventModifiers: eventModifiers)
    }

    private func performRoute(
        _ incomingRequest: RouteRequest,
        eventModifiers: NSEvent.ModifierFlags
    ) async {
        await browserCatalog.loadApplicationsIfNeeded()
        var request = incomingRequest
        let settings = settingsStore.settings.linkRouter
        logger.isEnabled = settings.logLevel != .off

        if applyBrowserPickerModifier(
            settings.browserPickerModifier,
            eventModifiers: eventModifiers,
            to: &request
        ) {
            logger.log(stage: "Input", "Browser-picker modifier was held; user rules are bypassed.")
        }
        if settings.openInBackgroundWhenControlHeld, eventModifiers.contains(.control) {
            request.openInBackground = true
        }
        if request.trigger == .browserExtension, settings.browserExtensionAlwaysPrompts {
            request.forcePrompt = true
        }

        let urlsToExpand = request.urls
        let expansionIsEnabled = settings.expandShortURLs
        let redirectLimit = settings.shortURLRedirectLimit
        async let pendingExpansions = shortURLExpander.expand(
            urlsToExpand,
            enabled: expansionIsEnabled,
            maximumRedirects: redirectLimit
        )
        let preparedRules: SafeRuleEvaluator.PreparedRules
        do {
            preparedRules = request.bypassRules ? .empty : try await prepareRules(settings.rules)
        } catch {
            logger.log(.error, stage: "Rule", error.localizedDescription)
            present(error)
            return
        }
        let expansions = await pendingExpansions
        var preparedURLs: [PreparedURL] = []
        for (originalURL, expansion) in zip(request.urls, expansions) {
            do {
                preparedURLs.append(
                    try prepareURL(
                        originalURL,
                        expansion: expansion,
                        settings: settings
                    ))
            } catch {
                logger.log(.error, stage: "Router", error.localizedDescription)
                present(error)
            }
        }

        let matches: [RuleMatch?]
        if request.bypassRules || request.forcePrompt || request.forcedTarget != nil {
            matches = Array(repeating: nil, count: preparedURLs.count)
        } else {
            do {
                matches = try await safeRuleEvaluator.firstMatches(
                    for: preparedURLs.map(\.workingURL),
                    sourceApplication: request.sourceApplication,
                    preparedRules: preparedRules
                )
            } catch {
                logger.log(.error, stage: "Rule", error.localizedDescription)
                present(error)
                return
            }
        }

        for (preparedURL, match) in zip(preparedURLs, matches) {
            do {
                try await routeSingle(
                    preparedURL,
                    match: match,
                    request: request,
                    settings: settings
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
        _ preparedURL: PreparedURL,
        match: RuleMatch?,
        request: RouteRequest,
        settings: LinkRouterSettings
    ) async throws {
        let originalURL = preparedURL.originalURL
        var workingURL = preparedURL.workingURL
        var trace = preparedURL.trace
        var matchedRule: LinkRule?
        var target: RouteTarget?
        var openInNewWindow = request.openInNewWindow
        var openInBackground = request.openInBackground

        if let forced = request.forcedTarget {
            target = forced
            trace.append(RoutingTraceStep(stage: "Target", message: "Forced target: \(forced.displayName)"))
        } else if request.forcePrompt {
            target = .prompt
        } else if let match {
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

        if target == nil,
            let webServiceTarget = targetResolver.webServiceTarget(for: workingURL, settings: settings)
        {
            target = webServiceTarget.target
            trace.append(RoutingTraceStep(stage: "Web Service", message: webServiceTarget.message))
        }

        if target == nil, settings.useNativeAppRouting,
            let native = targetResolver.nativeAppTarget(for: workingURL, enabledIDs: settings.enabledNativeAppIDs)
        {
            target = native.target
            workingURL = native.url
            trace.append(RoutingTraceStep(stage: "Native App", message: "Matched \(native.definition.displayName)."))
        }

        if target == nil {
            target = .primary
        }

        target = targetResolver.resolveSpecialTarget(target ?? .prompt, settings: settings)

        if target?.kind == .prompt {
            let selection = await promptController.choose(
                url: workingURL,
                targets: targetResolver.promptTargets(settings: settings),
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

    private func prepareURL(
        _ originalURL: URL,
        expansion: ShortURLExpansionResult,
        settings: LinkRouterSettings
    ) throws -> PreparedURL {
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

        return PreparedURL(originalURL: originalURL, workingURL: workingURL, trace: trace)
    }

    private func makeSanitizer(_ settings: LinkRouterSettings) -> URLSanitizer {
        URLSanitizer(
            additionalParameters: Set(settings.additionalTrackingParameters),
            allowedParameters: Set(settings.allowedTrackingParameters),
            removeTrackingParameters: settings.removeTrackingParameters,
            unwrapRedirects: settings.unwrapEmbeddedRedirects
        )
    }

    private func prepareRules(_ rules: [LinkRule]) async throws -> SafeRuleEvaluator.PreparedRules {
        guard cachedRules != rules else { return cachedPreparedRules }
        let prepared = try await safeRuleEvaluator.prepare(rules)
        cachedRules = rules
        cachedPreparedRules = prepared
        return prepared
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
