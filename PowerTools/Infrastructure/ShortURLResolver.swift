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

    private let session: URLSession
    private let hostValidator: PublicNetworkHostValidator
    private let cache = ResolutionCache()

    init(hostValidator: PublicNetworkHostValidator = PublicNetworkHostValidator()) {
        self.hostValidator = hostValidator
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpAdditionalHeaders = ["User-Agent": "PowerTools-LinkRouter/1.0"]
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func resolve(
        _ input: URL,
        customShortenerHosts: Set<String>,
        resolveUnknownRedirects: Bool,
        maximumRedirects: Int
    ) async throws -> URL {
        guard input.absoluteString.utf8.count <= 16_384,
            let scheme = input.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw ResolverError.unsupportedURL
        }

        let registry = ShortenerRegistry(customHosts: customShortenerHosts)
        guard registry.contains(input) || resolveUnknownRedirects else { return input }
        guard await hostValidator.allows(input) else { throw ResolverError.unsafeDestination }

        if let cached = await cache.value(for: input) {
            return cached
        }

        let headResult: URL?
        do {
            headResult = try await finalURL(
                for: request(url: input, method: "HEAD"),
                maximumRedirects: maximumRedirects
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
                for: request(url: input, method: "GET"),
                maximumRedirects: maximumRedirects
            )
        }

        await cache.insert(final, for: input)
        return final
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

    private func finalURL(for request: URLRequest, maximumRedirects: Int) async throws -> URL {
        let boundedRedirectLimit = min(max(maximumRedirects, 1), 50)
        let delegate = RedirectGuard(
            hostValidator: hostValidator,
            maximumRedirects: boundedRedirectLimit
        )
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        // `bytes(for:)` returns as soon as response headers arrive. Cancelling here avoids
        // buffering or downloading a body even when a server ignores the Range header.
        bytes.task.cancel()

        if let failure = delegate.failure {
            throw failure
        }
        guard let response = response as? HTTPURLResponse,
            let final = response.url,
            await hostValidator.allows(final)
        else {
            throw ResolverError.invalidResponse
        }
        return final
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let hostValidator: PublicNetworkHostValidator
    private let maximumRedirects: Int
    private let lock = NSLock()
    private var redirectCount = 0
    private var storedFailure: ShortURLResolver.ResolverError?

    init(hostValidator: PublicNetworkHostValidator, maximumRedirects: Int) {
        self.hostValidator = hostValidator
        self.maximumRedirects = maximumRedirects
    }

    var failure: ShortURLResolver.ResolverError? {
        lock.withLock { storedFailure }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let completion = RedirectCompletion(completionHandler)
        let exceedsLimit = lock.withLock { () -> Bool in
            redirectCount += 1
            return redirectCount > maximumRedirects
        }
        guard !exceedsLimit else {
            lock.withLock { storedFailure = .tooManyRedirects }
            completion.call(nil)
            return
        }

        Task {
            guard let destination = request.url,
                await hostValidator.allows(destination)
            else {
                lock.withLock { storedFailure = .unsafeDestination }
                completion.call(nil)
                return
            }
            completion.call(request)
        }
    }
}

private final class RedirectCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((URLRequest?) -> Void)?

    init(_ handler: @escaping (URLRequest?) -> Void) {
        self.handler = handler
    }

    func call(_ request: URLRequest?) {
        let callback = lock.withLock { () -> ((URLRequest?) -> Void)? in
            defer { handler = nil }
            return handler
        }
        callback?(request)
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
