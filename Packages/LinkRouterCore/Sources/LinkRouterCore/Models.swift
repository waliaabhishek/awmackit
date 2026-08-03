import Foundation

public struct SourceApplication: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var name: String
    public var processIdentifier: Int32?

    public init(bundleIdentifier: String?, name: String, processIdentifier: Int32? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
    }
}

public enum URLMatcherKind: String, Codable, CaseIterable, Sendable {
    case exact
    case host
    case hostSuffix
    case prefix
    case suffix
    case contains
    case regularExpression
    case pathPrefix
    case scheme
    case queryParameter
}

public struct URLMatcher: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: URLMatcherKind
    public var pattern: String
    public var isNegated: Bool
    public var isCaseSensitive: Bool

    public init(
        id: UUID = UUID(),
        kind: URLMatcherKind,
        pattern: String,
        isNegated: Bool = false,
        isCaseSensitive: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.isNegated = isNegated
        self.isCaseSensitive = isCaseSensitive
    }

    public func matches(_ url: URL) -> Bool {
        let result = rawMatch(url)
        return isNegated ? !result : result
    }

    private func rawMatch(_ url: URL) -> Bool {
        let absolute = url.absoluteString
        let comparisonPattern = isCaseSensitive ? pattern : pattern.lowercased()
        let comparisonAbsolute = isCaseSensitive ? absolute : absolute.lowercased()

        switch kind {
        case .exact:
            return comparisonAbsolute == comparisonPattern
        case .host:
            guard let host = url.host else { return false }
            return (isCaseSensitive ? host : host.lowercased()) == comparisonPattern
        case .hostSuffix:
            guard let host = url.host else { return false }
            let normalizedHost = isCaseSensitive ? host : host.lowercased()
            let normalizedPattern = comparisonPattern.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return normalizedHost == normalizedPattern || normalizedHost.hasSuffix(".\(normalizedPattern)")
        case .prefix:
            return comparisonAbsolute.hasPrefix(comparisonPattern)
        case .suffix:
            return comparisonAbsolute.hasSuffix(comparisonPattern)
        case .contains:
            return comparisonAbsolute.contains(comparisonPattern)
        case .regularExpression:
            let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
                return false
            }
            let range = NSRange(absolute.startIndex..<absolute.endIndex, in: absolute)
            return expression.firstMatch(in: absolute, range: range) != nil
        case .pathPrefix:
            let path = isCaseSensitive ? url.path : url.path.lowercased()
            return path.hasPrefix(comparisonPattern)
        case .scheme:
            let scheme = isCaseSensitive ? url.scheme : url.scheme?.lowercased()
            return scheme == comparisonPattern
        case .queryParameter:
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return false
            }
            let pieces = pattern.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let expectedName = String(pieces[0])
            let expectedValue = pieces.count == 2 ? String(pieces[1]) : nil
            return (components.queryItems ?? []).contains { item in
                let nameMatches = compare(item.name, expectedName)
                guard nameMatches else { return false }
                guard let expectedValue else { return true }
                return compare(item.value ?? "", expectedValue)
            }
        }
    }

    private func compare(_ lhs: String, _ rhs: String) -> Bool {
        isCaseSensitive ? lhs == rhs : lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}

public enum URLMatcherGroupMode: String, Codable, CaseIterable, Sendable {
    case any
    case all
}

public struct URLMatcherGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var mode: URLMatcherGroupMode
    public var matchers: [URLMatcher]

    public init(
        id: UUID = UUID(),
        mode: URLMatcherGroupMode,
        matchers: [URLMatcher]
    ) {
        self.id = id
        self.mode = mode
        self.matchers = matchers
    }

    public func matches(_ url: URL) -> Bool {
        switch mode {
        case .any:
            return !matchers.isEmpty && matchers.contains { $0.matches(url) }
        case .all:
            return matchers.allSatisfy { $0.matches(url) }
        }
    }
}

public struct SourceAppMatcher: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var isNegated: Bool

    public init(id: UUID = UUID(), bundleIdentifier: String, isNegated: Bool = false) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.isNegated = isNegated
    }

    public func matches(_ source: SourceApplication?) -> Bool {
        let match = source?.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        return isNegated ? !match : match
    }
}

public enum BrowserOpenMode: String, Codable, CaseIterable, Sendable {
    case normal
    case privateWindow
}

public enum RouteTargetKind: String, Codable, CaseIterable, Sendable {
    case primaryBrowser
    case alternativeBrowser
    case prompt
    case application
    case browserProfile
    case browserPWA
    case copyURL
    case share
    case systemDefault
    case discard
}

public struct RouteTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: RouteTargetKind
    public var displayName: String
    public var bundleIdentifier: String?
    public var applicationPath: String?
    public var profileIdentifier: String?
    public var profileName: String?
    public var pwaIdentifier: String?
    public var pwaApplicationPath: String?
    public var openMode: BrowserOpenMode

    public init(
        id: String,
        kind: RouteTargetKind,
        displayName: String,
        bundleIdentifier: String? = nil,
        applicationPath: String? = nil,
        profileIdentifier: String? = nil,
        profileName: String? = nil,
        pwaIdentifier: String? = nil,
        pwaApplicationPath: String? = nil,
        openMode: BrowserOpenMode = .normal
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.profileIdentifier = profileIdentifier
        self.profileName = profileName
        self.pwaIdentifier = pwaIdentifier
        self.pwaApplicationPath = pwaApplicationPath
        self.openMode = openMode
    }

    public static let prompt = RouteTarget(id: "special.prompt", kind: .prompt, displayName: "Ask Every Time")
    public static let primary = RouteTarget(
        id: "special.primary", kind: .primaryBrowser, displayName: "Primary Browser")
    public static let alternative = RouteTarget(
        id: "special.alternative", kind: .alternativeBrowser, displayName: "Alternative Browser")
    public static let copyURL = RouteTarget(id: "special.copy", kind: .copyURL, displayName: "Copy URL")
    public static let share = RouteTarget(id: "special.share", kind: .share, displayName: "Share")
    public static let discard = RouteTarget(id: "special.discard", kind: .discard, displayName: "Do Nothing")
}

public struct LinkRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var priority: Int
    public var urlMatchers: [URLMatcher]
    /// Version 2 condition groups. When present, groups are combined with AND while
    /// each group controls whether any or all of its matchers must match.
    public var urlMatcherGroups: [URLMatcherGroup]?
    public var sourceAppMatchers: [SourceAppMatcher]
    public var target: RouteTarget
    public var rewriteActions: [URLRewriteAction]?
    public var editorKind: RuleEditorKind?
    public var websiteFamilyID: String?
    public var transformJavaScript: String?
    public var openInNewWindow: Bool
    public var openInBackground: Bool
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        urlMatchers: [URLMatcher] = [],
        urlMatcherGroups: [URLMatcherGroup]? = nil,
        sourceAppMatchers: [SourceAppMatcher] = [],
        target: RouteTarget,
        rewriteActions: [URLRewriteAction]? = nil,
        editorKind: RuleEditorKind? = nil,
        websiteFamilyID: String? = nil,
        transformJavaScript: String? = nil,
        openInNewWindow: Bool = false,
        openInBackground: Bool = false,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.urlMatchers = urlMatchers
        self.urlMatcherGroups = urlMatcherGroups
        self.sourceAppMatchers = sourceAppMatchers
        self.target = target
        self.rewriteActions = rewriteActions
        self.editorKind = editorKind
        self.websiteFamilyID = websiteFamilyID
        self.transformJavaScript = transformJavaScript
        self.openInNewWindow = openInNewWindow
        self.openInBackground = openInBackground
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func matches(url: URL, sourceApplication: SourceApplication?) -> Bool {
        guard isEnabled else { return false }
        let urlMatches: Bool
        if let urlMatcherGroups {
            urlMatches = urlMatcherGroups.isEmpty || urlMatcherGroups.allSatisfy { $0.matches(url) }
        } else {
            urlMatches = urlMatchers.isEmpty || urlMatchers.allSatisfy { $0.matches(url) }
        }

        // Positive source-application matchers are alternatives (Slack OR Mail), while
        // negated matchers are exclusions that must all pass. This mirrors how a user
        // naturally builds one rule for several source applications.
        let positiveSourceMatchers = sourceAppMatchers.filter { !$0.isNegated }
        let negativeSourceMatchers = sourceAppMatchers.filter(\.isNegated)
        let positiveSourceMatches =
            positiveSourceMatchers.isEmpty
            || positiveSourceMatchers.contains { $0.matches(sourceApplication) }
        let negativeSourceMatches = negativeSourceMatchers.allSatisfy { $0.matches(sourceApplication) }

        return urlMatches && positiveSourceMatches && negativeSourceMatches
    }
}

public struct RuleMatch: Hashable, Sendable {
    public var rule: LinkRule
    public var target: RouteTarget

    public init(rule: LinkRule, target: RouteTarget) {
        self.rule = rule
        self.target = target
    }
}

public enum RouterTrigger: String, Codable, Sendable {
    case systemLink
    case customURLScheme
    case clipboard
    case shareExtension
    case browserExtension
    case service
    case shortcut
    case handoff
    case manual
}

public struct RouteRequest: Sendable {
    public var urls: [URL]
    public var sourceApplication: SourceApplication?
    public var trigger: RouterTrigger
    public var forcePrompt: Bool
    public var forcedTarget: RouteTarget?
    public var openInBackground: Bool
    public var openInNewWindow: Bool
    public var bypassRules: Bool

    public init(
        urls: [URL],
        sourceApplication: SourceApplication? = nil,
        trigger: RouterTrigger = .systemLink,
        forcePrompt: Bool = false,
        forcedTarget: RouteTarget? = nil,
        openInBackground: Bool = false,
        openInNewWindow: Bool = false,
        bypassRules: Bool = false
    ) {
        self.urls = urls
        self.sourceApplication = sourceApplication
        self.trigger = trigger
        self.forcePrompt = forcePrompt
        self.forcedTarget = forcedTarget
        self.openInBackground = openInBackground
        self.openInNewWindow = openInNewWindow
        self.bypassRules = bypassRules
    }
}

public struct RoutingTraceStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var stage: String
    public var message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), stage: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.stage = stage
        self.message = message
    }
}

public struct RouteDecision: Sendable {
    public var originalURL: URL
    public var finalURL: URL
    public var sourceApplication: SourceApplication?
    public var target: RouteTarget
    public var matchedRule: LinkRule?
    public var openInBackground: Bool
    public var openInNewWindow: Bool
    public var trace: [RoutingTraceStep]

    public init(
        originalURL: URL,
        finalURL: URL,
        sourceApplication: SourceApplication?,
        target: RouteTarget,
        matchedRule: LinkRule? = nil,
        openInBackground: Bool = false,
        openInNewWindow: Bool = false,
        trace: [RoutingTraceStep] = []
    ) {
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.sourceApplication = sourceApplication
        self.target = target
        self.matchedRule = matchedRule
        self.openInBackground = openInBackground
        self.openInNewWindow = openInNewWindow
        self.trace = trace
    }
}
