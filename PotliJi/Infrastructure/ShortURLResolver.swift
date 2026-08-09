import Foundation
import LinkRouterCore

final class ShortURLResolver: @unchecked Sendable {
    enum ResolverError: LocalizedError {
        case unsupportedURL
        case unsafeDestination
        case tooManyRedirects
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unsupportedURL:
                "The URL cannot be resolved safely."
            case .unsafeDestination:
                "The redirect points to a private or reserved network address."
            case .tooManyRedirects:
                "The redirect chain exceeded the safety limit."
            case .invalidResponse:
                "The redirect service returned an invalid response."
            }
        }
    }

    enum RedirectDecision: Equatable {
        case fetch(URL)
        case finish(URL)
    }

    private let session: URLSession
    private let hostValidator: PublicNetworkHostValidator
    private let cache = ResolutionCache()

    init(hostValidator: PublicNetworkHostValidator = PublicNetworkHostValidator()) {
        self.hostValidator = hostValidator
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpAdditionalHeaders = ["User-Agent": "PotliJi-LinkRouter/1.0"]
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func resolve(
        _ input: URL,
        maximumRedirects: Int
    ) async throws -> URL {
        guard Self.isSupportedWebURL(input) else {
            throw ResolverError.unsupportedURL
        }

        let registry = ShortenerRegistry()
        // Restrict network access to a hard-coded trust boundary. A DNS preflight
        // cannot safely pin an arbitrary host to the address URLSession connects to.
        guard registry.containsBuiltIn(input) else { return input }
        guard await hostValidator.allows(input) else { throw ResolverError.unsafeDestination }

        if let cached = await cache.value(for: input) {
            return cached
        }

        let headResult: URL?
        do {
            headResult = try await finalURL(
                for: input,
                method: "HEAD",
                maximumRedirects: maximumRedirects,
                registry: registry
            )
        } catch let error as ResolverError {
            throw error
        } catch {
            headResult = nil
        }

        let final: URL
        if let headResult, headResult != input {
            final = headResult
        } else {
            final = try await finalURL(
                for: input,
                method: "GET",
                maximumRedirects: maximumRedirects,
                registry: registry
            )
        }

        await cache.insert(final, for: input)
        return final
    }

    static func redirectDecision(
        from currentURL: URL,
        location: String,
        registry: ShortenerRegistry = ShortenerRegistry()
    ) throws -> RedirectDecision {
        guard let destination = URL(string: location, relativeTo: currentURL)?.absoluteURL,
            isSupportedWebURL(destination)
        else {
            throw ResolverError.invalidResponse
        }
        return registry.containsBuiltIn(destination) ? .fetch(destination) : .finish(destination)
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 16_384,
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "GET" {
            // The response body is never consumed, but the header remains useful for servers
            // that require a range request before issuing their redirect.
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        }
        return request
    }

    private func finalURL(
        for input: URL,
        method: String,
        maximumRedirects: Int,
        registry: ShortenerRegistry
    ) async throws -> URL {
        let boundedRedirectLimit = min(max(maximumRedirects, 1), 50)
        var current = input
        var redirectCount = 0

        while true {
            guard registry.containsBuiltIn(current),
                await hostValidator.allows(current)
            else {
                throw ResolverError.unsafeDestination
            }

            let (bytes, response) = try await session.bytes(
                for: request(url: current, method: method),
                delegate: RedirectStopper()
            )
            // `bytes(for:)` returns as soon as response headers arrive. Cancelling here avoids
            // buffering or downloading a body even when a server ignores the Range header.
            bytes.task.cancel()

            guard let response = response as? HTTPURLResponse else {
                throw ResolverError.invalidResponse
            }
            guard (300..<400).contains(response.statusCode) else { return current }
            guard let location = response.value(forHTTPHeaderField: "Location") else {
                throw ResolverError.invalidResponse
            }

            let decision = try Self.redirectDecision(
                from: response.url ?? current,
                location: location,
                registry: registry
            )
            switch decision {
            case .finish(let destination):
                // The arbitrary destination is returned to the browser without PotliJi
                // connecting to it. This is the SSRF/DNS-rebinding security boundary.
                guard await hostValidator.allows(destination) else {
                    throw ResolverError.unsafeDestination
                }
                return destination
            case .fetch(let destination):
                redirectCount += 1
                guard redirectCount <= boundedRedirectLimit else {
                    throw ResolverError.tooManyRedirects
                }
                current = destination
            }
        }
    }
}

private final class RedirectStopper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private actor ResolutionCache {
    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private var entries: [URL: Entry] = [:]
    private let lifetime: TimeInterval = 15 * 60

    func value(for input: URL, now: Date = Date()) -> URL? {
        guard let entry = entries[input] else { return nil }
        guard entry.expiresAt > now else {
            entries[input] = nil
            return nil
        }
        return entry.url
    }

    func insert(_ result: URL, for input: URL, now: Date = Date()) {
        entries[input] = Entry(url: result, expiresAt: now.addingTimeInterval(lifetime))
        if entries.count > 512 {
            entries = entries.filter { $0.value.expiresAt > now }
            while entries.count > 512,
                let oldestKey = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key
            {
                entries[oldestKey] = nil
            }
        }
    }
}
