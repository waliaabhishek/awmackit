import Foundation
import LinkRouterCore

struct SafeRuleEvaluator {
    struct PreparedRules: Sendable {
        fileprivate let orderedRules: [LinkRule]
        fileprivate let requiresIsolatedEvaluation: [Bool]
        fileprivate let isolatedRules: [LinkRule]

        static let empty = PreparedRules(
            orderedRules: [],
            requiresIsolatedEvaluation: [],
            isolatedRules: []
        )
    }

    enum EvaluationError: LocalizedError {
        case helperUnavailable
        case helperFailed(String)
        case invalidResponse
        case requestTooLarge(Int)

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                "The isolated rule-matching helper could not be located."
            case .helperFailed(let message):
                "The isolated rule-matching helper failed: \(message)"
            case .invalidResponse:
                "The isolated rule-matching helper returned an invalid result."
            case .requestTooLarge(let byteCount):
                "The rule-matching request is \(byteCount) bytes; the maximum is \(RuleMatchHelper.maximumRequestBytes)."
            }
        }
    }

    private let ruleEngine = RuleEngine()

    func prepare(_ rules: [LinkRule]) async throws -> PreparedRules {
        try await Task.detached(priority: .userInitiated) { [ruleEngine] in
            try RuleTransfer().validate(rules)
            let orderedRules = ruleEngine.ordered(rules)
            let isolated = orderedRules.map { rule in
                guard rule.isEnabled else { return false }
                let matchers = rule.urlMatcherGroups?.flatMap(\.matchers) ?? rule.urlMatchers
                return matchers.contains { $0.kind == .regularExpression }
            }
            return PreparedRules(
                orderedRules: orderedRules,
                requiresIsolatedEvaluation: isolated,
                isolatedRules: zip(orderedRules, isolated).compactMap { rule, isIsolated in
                    isIsolated ? rule : nil
                }
            )
        }.value
    }

    func firstMatch(
        for url: URL,
        sourceApplication: SourceApplication?,
        preparedRules: PreparedRules
    ) async throws -> RuleMatch? {
        try await firstMatches(
            for: [url],
            sourceApplication: sourceApplication,
            preparedRules: preparedRules
        )[0]
    }

    func firstMatches(
        for urls: [URL],
        sourceApplication: SourceApplication?,
        preparedRules: PreparedRules
    ) async throws -> [RuleMatch?] {
        guard !urls.isEmpty else { return [] }

        let plans = urls.map { url in
            var isolatedCandidateCount = 0
            var localMatch: LinkRule?
            for (index, rule) in preparedRules.orderedRules.enumerated() {
                if preparedRules.requiresIsolatedEvaluation[index] {
                    isolatedCandidateCount += 1
                } else if rule.matches(url: url, sourceApplication: sourceApplication) {
                    localMatch = rule
                    break
                }
            }
            return RuleEvaluationPlan(
                url: url,
                isolatedCandidateCount: isolatedCandidateCount,
                localMatch: localMatch
            )
        }

        guard plans.contains(where: { $0.isolatedCandidateCount > 0 }) else {
            return plans.map { $0.localMatch.map { RuleMatch(rule: $0, target: $0.target) } }
        }
        guard let executableURL = Bundle.main.executableURL else {
            throw EvaluationError.helperUnavailable
        }

        let helperInputs = plans.map {
            RuleMatchHelperInput(
                url: $0.url,
                sourceApplication: sourceApplication,
                isolatedCandidateCount: $0.isolatedCandidateCount
            )
        }
        var matchedRuleIDs: [UUID?] = []
        for startIndex in stride(from: 0, to: helperInputs.count, by: RuleMatchHelper.maximumBatchSize) {
            let endIndex = min(startIndex + RuleMatchHelper.maximumBatchSize, helperInputs.count)
            matchedRuleIDs += try await isolatedMatches(
                inputs: Array(helperInputs[startIndex..<endIndex]),
                orderedRules: preparedRules.isolatedRules,
                executableURL: executableURL
            )
        }
        let rulesByID = Dictionary(uniqueKeysWithValues: preparedRules.isolatedRules.map { ($0.id, $0) })
        return try zip(plans, matchedRuleIDs).map { plan, matchedRuleID in
            if let matchedRuleID {
                guard let rule = rulesByID[matchedRuleID] else {
                    throw EvaluationError.invalidResponse
                }
                return RuleMatch(rule: rule, target: rule.target)
            }
            return plan.localMatch.map { RuleMatch(rule: $0, target: $0.target) }
        }
    }

    private func isolatedMatches(
        inputs: [RuleMatchHelperInput],
        orderedRules: [LinkRule],
        executableURL: URL
    ) async throws -> [UUID?] {
        let request = RuleMatchHelperRequest(inputs: inputs, orderedRules: orderedRules)
        let input = try await Task.detached(priority: .userInitiated) {
            try JSONEncoder().encode(request)
        }.value
        if input.count > RuleMatchHelper.maximumRequestBytes, inputs.count > 1 {
            let midpoint = inputs.count / 2
            let first = try await isolatedMatches(
                inputs: Array(inputs[..<midpoint]),
                orderedRules: orderedRules,
                executableURL: executableURL
            )
            let second = try await isolatedMatches(
                inputs: Array(inputs[midpoint...]),
                orderedRules: orderedRules,
                executableURL: executableURL
            )
            return first + second
        }
        guard input.count <= RuleMatchHelper.maximumRequestBytes else {
            throw EvaluationError.requestTooLarge(input.count)
        }

        let output = try await AsyncProcessRunner.run(
            executableURL: executableURL,
            arguments: [RuleMatchHelper.argument],
            input: input,
            timeout: 1
        )
        guard output.terminationStatus == 0 else {
            let message = String(decoding: output.standardError, as: UTF8.self)
            throw EvaluationError.helperFailed(message.isEmpty ? "Exit status \(output.terminationStatus)" : message)
        }
        let response = try JSONDecoder().decode(RuleMatchHelperResponse.self, from: output.standardOutput)
        guard response.matchedRuleIDs.count == inputs.count else {
            throw EvaluationError.invalidResponse
        }
        return response.matchedRuleIDs
    }
}

private struct RuleEvaluationPlan {
    let url: URL
    let isolatedCandidateCount: Int
    let localMatch: LinkRule?
}

private struct RuleMatchHelperInput: Codable, Sendable {
    let url: URL
    let sourceApplication: SourceApplication?
    let isolatedCandidateCount: Int
}

private struct RuleMatchHelperRequest: Codable, Sendable {
    let inputs: [RuleMatchHelperInput]
    let orderedRules: [LinkRule]
}

private struct RuleMatchHelperResponse: Codable, Sendable {
    let matchedRuleIDs: [UUID?]
}

enum RuleMatchHelper {
    static let argument = "--powertools-rule-match-helper"
    static let maximumBatchSize = 128
    // A valid settings document can contain 16 MB of rules. The helper request uses
    // compact JSON, but retain envelope space for the routed URL and source metadata.
    static let maximumRequestBytes = RuleTransfer.maximumDocumentBytes + 4 * 1_024 * 1_024

    static func run() -> Int32 {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= maximumRequestBytes else {
                throw SafeRuleEvaluator.EvaluationError.requestTooLarge(data.count)
            }
            let request = try JSONDecoder().decode(RuleMatchHelperRequest.self, from: data)
            try RuleTransfer().validate(request.orderedRules)
            let matcher = try PreparedIsolatedRuleMatcher(rules: request.orderedRules)
            let matchedRuleIDs = request.inputs.map { input in
                matcher.firstMatch(
                    for: input.url,
                    sourceApplication: input.sourceApplication,
                    candidateCount: input.isolatedCandidateCount
                )?.id
            }
            let response = RuleMatchHelperResponse(matchedRuleIDs: matchedRuleIDs)
            FileHandle.standardOutput.write(try JSONEncoder().encode(response))
            return 0
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            return 1
        }
    }
}

private struct PreparedIsolatedRuleMatcher {
    private let rules: [LinkRule]
    private let expressions: [UUID: NSRegularExpression]

    init(rules: [LinkRule]) throws {
        self.rules = rules
        var expressions: [UUID: NSRegularExpression] = [:]
        for matcher in rules.flatMap(Self.urlMatchers) where matcher.kind == .regularExpression {
            let options: NSRegularExpression.Options = matcher.isCaseSensitive ? [] : [.caseInsensitive]
            expressions[matcher.id] = try NSRegularExpression(pattern: matcher.pattern, options: options)
        }
        self.expressions = expressions
    }

    func firstMatch(
        for url: URL,
        sourceApplication: SourceApplication?,
        candidateCount: Int
    ) -> LinkRule? {
        rules.prefix(candidateCount).first {
            matches($0, url: url, sourceApplication: sourceApplication)
        }
    }

    private func matches(
        _ rule: LinkRule,
        url: URL,
        sourceApplication: SourceApplication?
    ) -> Bool {
        guard rule.isEnabled else { return false }
        let urlMatches: Bool
        if let groups = rule.urlMatcherGroups {
            urlMatches =
                groups.isEmpty
                || groups.allSatisfy { group in
                    switch group.mode {
                    case .any:
                        !group.matchers.isEmpty && group.matchers.contains { matches($0, url: url) }
                    case .all:
                        group.matchers.allSatisfy { matches($0, url: url) }
                    }
                }
        } else {
            urlMatches = rule.urlMatchers.isEmpty || rule.urlMatchers.allSatisfy { matches($0, url: url) }
        }

        let positiveSourceMatchers = rule.sourceAppMatchers.filter { !$0.isNegated }
        let negativeSourceMatchers = rule.sourceAppMatchers.filter(\.isNegated)
        let positiveSourceMatches =
            positiveSourceMatchers.isEmpty
            || positiveSourceMatchers.contains { $0.matches(sourceApplication) }
        let negativeSourceMatches = negativeSourceMatchers.allSatisfy { $0.matches(sourceApplication) }
        return urlMatches && positiveSourceMatches && negativeSourceMatches
    }

    private func matches(_ matcher: URLMatcher, url: URL) -> Bool {
        guard matcher.kind == .regularExpression else { return matcher.matches(url) }
        guard let expression = expressions[matcher.id] else { return false }
        let absolute = url.absoluteString
        let range = NSRange(absolute.startIndex..<absolute.endIndex, in: absolute)
        let matches = expression.firstMatch(in: absolute, range: range) != nil
        return matcher.isNegated ? !matches : matches
    }

    private static func urlMatchers(in rule: LinkRule) -> [URLMatcher] {
        rule.urlMatcherGroups?.flatMap(\.matchers) ?? rule.urlMatchers
    }
}
