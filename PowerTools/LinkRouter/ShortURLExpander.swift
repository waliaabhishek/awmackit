import Foundation

struct ShortURLExpansionResult: Sendable {
    let url: URL
    let errorMessage: String?
}

final class ShortURLExpander: @unchecked Sendable {
    private let resolver: ShortURLResolver

    init(resolver: ShortURLResolver = ShortURLResolver()) {
        self.resolver = resolver
    }

    func expand(
        _ urls: [URL],
        enabled: Bool,
        maximumRedirects: Int
    ) async -> [ShortURLExpansionResult] {
        guard enabled, !urls.isEmpty else {
            return urls.map { ShortURLExpansionResult(url: $0, errorMessage: nil) }
        }

        let concurrencyLimit = min(4, urls.count)
        var results = Array<ShortURLExpansionResult?>(repeating: nil, count: urls.count)

        await withTaskGroup(of: (Int, ShortURLExpansionResult).self) { group in
            var nextIndex = 0
            for _ in 0..<concurrencyLimit {
                addExpansion(at: nextIndex, from: urls, maximumRedirects: maximumRedirects, to: &group)
                nextIndex += 1
            }

            while let (completedIndex, result) = await group.next() {
                results[completedIndex] = result
                guard nextIndex < urls.count else { continue }
                addExpansion(at: nextIndex, from: urls, maximumRedirects: maximumRedirects, to: &group)
                nextIndex += 1
            }
        }

        return zip(urls, results).map { original, result in
            result ?? ShortURLExpansionResult(url: original, errorMessage: "Expansion was cancelled.")
        }
    }

    private func addExpansion(
        at index: Int,
        from urls: [URL],
        maximumRedirects: Int,
        to group: inout TaskGroup<(Int, ShortURLExpansionResult)>
    ) {
        let url = urls[index]
        group.addTask { [resolver] in
            do {
                let expanded = try await resolver.resolve(url, maximumRedirects: maximumRedirects)
                return (index, ShortURLExpansionResult(url: expanded, errorMessage: nil))
            } catch {
                return (
                    index,
                    ShortURLExpansionResult(url: url, errorMessage: error.localizedDescription)
                )
            }
        }
    }
}
