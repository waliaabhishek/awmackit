import Foundation
import LinkRouterCore

struct SafeRuleEvaluator {
    enum EvaluationError: LocalizedError {
        case helperUnavailable
        case helperFailed(String)
        case invalidResponse
        case requestTooLarge

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                "The isolated rule-matching helper could not be located."
            case .helperFailed(let message):
                "The isolated rule-matching helper failed: \(message)"
            case .invalidResponse:
                "The isolated rule-matching helper returned an invalid result."
            case .requestTooLarge:
                "The rule-matching request exceeded 2 MB."
            }
        }
    }

    private let ruleEngine = RuleEngine()

    func firstMatch(
        for url: URL,
        sourceApplication: SourceApplication?,
        orderedRules: [LinkRule]
    ) async throws -> RuleMatch? {
        let hasEnabledRegularExpression = orderedRules.contains { rule in
            let matchers = rule.urlMatcherGroups?.flatMap(\.matchers) ?? rule.urlMatchers
            return rule.isEnabled && matchers.contains { $0.kind == .regularExpression }
        }
        let enabledMatcherCount = orderedRules.lazy.filter(\.isEnabled).reduce(into: 0) { count, rule in
            count +=
                (rule.urlMatcherGroups?.flatMap(\.matchers).count ?? rule.urlMatchers.count)
                + rule.sourceAppMatchers.count
        }
        let requiresIsolatedHelper = hasEnabledRegularExpression || enabledMatcherCount > 512
        guard requiresIsolatedHelper else {
            return try await Task.detached(priority: .userInitiated) {
                try RuleTransfer().validate(orderedRules)
                return ruleEngine.firstMatch(
                    for: url,
                    sourceApplication: sourceApplication,
                    orderedRules: orderedRules
                )
            }.value
        }
        guard let executableURL = Bundle.main.executableURL else {
            throw EvaluationError.helperUnavailable
        }

        let request = RuleMatchHelperRequest(
            url: url,
            sourceApplication: sourceApplication,
            orderedRules: orderedRules
        )
        let input = try await Task.detached(priority: .userInitiated) {
            try JSONEncoder().encode(request)
        }.value
        guard input.count <= RuleMatchHelper.maximumRequestBytes else {
            throw EvaluationError.requestTooLarge
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
        guard let matchedRuleID = response.matchedRuleID else { return nil }
        guard let rule = orderedRules.first(where: { $0.id == matchedRuleID }) else {
            throw EvaluationError.invalidResponse
        }
        return RuleMatch(rule: rule, target: rule.target)
    }
}

private struct RuleMatchHelperRequest: Codable, Sendable {
    let url: URL
    let sourceApplication: SourceApplication?
    let orderedRules: [LinkRule]
}

private struct RuleMatchHelperResponse: Codable, Sendable {
    let matchedRuleID: UUID?
}

enum RuleMatchHelper {
    static let argument = "--powertools-rule-match-helper"
    static let maximumRequestBytes = 2 * 1_024 * 1_024

    static func run() -> Int32 {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= maximumRequestBytes else {
                throw SafeRuleEvaluator.EvaluationError.requestTooLarge
            }
            let request = try JSONDecoder().decode(RuleMatchHelperRequest.self, from: data)
            try RuleTransfer().validate(request.orderedRules)
            let match = RuleEngine().firstMatch(
                for: request.url,
                sourceApplication: request.sourceApplication,
                orderedRules: request.orderedRules
            )
            let response = RuleMatchHelperResponse(matchedRuleID: match?.rule.id)
            FileHandle.standardOutput.write(try JSONEncoder().encode(response))
            return 0
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            return 1
        }
    }
}
