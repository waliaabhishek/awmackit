import Foundation
import JavaScriptCore
import LinkRouterCore

struct JavaScriptURLTransformer {
    enum TransformError: LocalizedError {
        case couldNotCreateContext
        case scriptException(String)
        case invalidOutput
        case scriptTooLarge
        case helperUnavailable
        case helperFailed(String)

        var errorDescription: String? {
            switch self {
            case .couldNotCreateContext:
                "Could not create the JavaScript environment."
            case .scriptException(let message):
                "JavaScript transform failed: \(message)"
            case .invalidOutput:
                "The JavaScript transform did not produce a valid URL."
            case .scriptTooLarge:
                "JavaScript transforms are limited to 64 KB."
            case .helperUnavailable:
                "The isolated JavaScript helper could not be located."
            case .helperFailed(let message):
                "The isolated JavaScript helper failed: \(message)"
            }
        }
    }

    func transform(
        url: URL,
        sourceApplication: SourceApplication?,
        script: String
    ) async throws -> URL {
        guard script.utf8.count <= TransformHelperRequest.maximumScriptBytes else {
            throw TransformError.scriptTooLarge
        }
        guard let executableURL = Bundle.main.executableURL else {
            throw TransformError.helperUnavailable
        }

        let request = TransformHelperRequest(
            url: url,
            sourceApplication: sourceApplication,
            script: script
        )
        let input = try await Task.detached(priority: .userInitiated) {
            try JSONEncoder().encode(request)
        }.value
        let output = try await AsyncProcessRunner.run(
            executableURL: executableURL,
            arguments: [TransformHelper.argument],
            input: input,
            timeout: 1
        )
        guard output.terminationStatus == 0 else {
            let message = String(decoding: output.standardError, as: UTF8.self)
            throw TransformError.helperFailed(message.isEmpty ? "Exit status \(output.terminationStatus)" : message)
        }

        let response = try JSONDecoder().decode(TransformHelperResponse.self, from: output.standardOutput)
        if let error = response.error {
            throw TransformError.scriptException(error)
        }
        guard let transformedURL = response.url,
            let scheme = transformedURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            throw TransformError.invalidOutput
        }
        return transformedURL
    }
}

struct TransformHelperRequest: Codable, Sendable {
    static let maximumScriptBytes = 64 * 1_024

    let url: URL
    let sourceApplication: SourceApplication?
    let script: String
}

private struct TransformHelperResponse: Codable, Sendable {
    let url: URL?
    let error: String?
}

enum TransformHelper {
    static let argument = "--potliji-transform-helper"

    static func run() -> Int32 {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(TransformHelperRequest.self, from: input)
            guard request.script.utf8.count <= TransformHelperRequest.maximumScriptBytes else {
                throw JavaScriptURLTransformer.TransformError.scriptTooLarge
            }
            let result = try InProcessJavaScriptTransformer().transform(
                url: request.url,
                sourceApplication: request.sourceApplication,
                script: request.script
            )
            try write(TransformHelperResponse(url: result, error: nil))
            return 0
        } catch {
            do {
                try write(TransformHelperResponse(url: nil, error: error.localizedDescription))
                return 0
            } catch {
                FileHandle.standardError.write(Data(error.localizedDescription.utf8))
                return 1
            }
        }
    }

    private static func write(_ response: TransformHelperResponse) throws {
        let data = try JSONEncoder().encode(response)
        guard data.count <= 128 * 1_024 else {
            throw JavaScriptURLTransformer.TransformError.invalidOutput
        }
        FileHandle.standardOutput.write(data)
    }
}

private struct InProcessJavaScriptTransformer {
    func transform(
        url: URL,
        sourceApplication: SourceApplication?,
        script: String
    ) throws -> URL {
        guard let context = JSContext() else {
            throw JavaScriptURLTransformer.TransformError.couldNotCreateContext
        }
        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "Unknown JavaScript exception"
        }

        let sourceObject: [String: Any] = [
            "name": sourceApplication?.name ?? NSNull(),
            "bundleIdentifier": sourceApplication?.bundleIdentifier ?? NSNull(),
        ]
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let hostname = components?.host ?? ""
        let host = components?.port.map { "\(hostname):\($0)" } ?? hostname
        let urlObject: [String: Any] = [
            "href": url.absoluteString,
            "protocol": components?.scheme.map { "\($0):" } ?? "",
            "username": components?.user ?? "",
            "password": components?.password ?? "",
            "hostname": hostname,
            "host": host,
            "port": components?.port.map(String.init) ?? "",
            "pathname": components?.percentEncodedPath ?? "",
            "search": components?.percentEncodedQuery.map { "?\($0)" } ?? "",
            "hash": components?.percentEncodedFragment.map { "#\($0)" } ?? "",
            "origin": components.flatMap { value in
                guard let scheme = value.scheme, let host = value.host else { return nil }
                return "\(scheme)://\(host)\(value.port.map { ":\($0)" } ?? "")"
            } ?? "",
        ]
        let input: [String: Any] = ["url": urlObject, "sourceApp": sourceObject]
        let data = try JSONSerialization.data(withJSONObject: input)
        let json = String(decoding: data, as: UTF8.self)

        let wrapped = """
            class URL {
                constructor(value) { this.href = String(value); }
                toString() { return this.href; }
            }
            var $ = \(json);
            (function () {
            \(script)
            }).call($);
            JSON.stringify($.url);
            """

        let value = context.evaluateScript(wrapped)
        if let exceptionMessage {
            throw JavaScriptURLTransformer.TransformError.scriptException(exceptionMessage)
        }
        guard let outputJSON = value?.toString(),
            outputJSON.utf8.count <= 128 * 1_024,
            let outputData = outputJSON.data(using: .utf8)
        else {
            throw JavaScriptURLTransformer.TransformError.invalidOutput
        }
        let outputValue = try JSONSerialization.jsonObject(with: outputData)
        if let directURL = outputValue as? String, let transformed = URL(string: directURL) {
            return transformed
        }
        guard let output = outputValue as? [String: Any] else {
            throw JavaScriptURLTransformer.TransformError.invalidOutput
        }

        if let href = output["href"] as? String,
            href != url.absoluteString,
            let transformed = URL(string: href)
        {
            return transformed
        }

        var rebuilt = components ?? URLComponents()
        if let protocolValue = output["protocol"] as? String {
            rebuilt.scheme = protocolValue.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        }
        if let username = output["username"] as? String { rebuilt.user = username.isEmpty ? nil : username }
        if let password = output["password"] as? String { rebuilt.password = password.isEmpty ? nil : password }

        let originalHostname = components?.host ?? ""
        let originalHost = components?.port.map { "\(originalHostname):\($0)" } ?? originalHostname
        let outputHostname = output["hostname"] as? String
        let outputHost = output["host"] as? String
        if let outputHostname, outputHostname != originalHostname {
            rebuilt.host = outputHostname
        } else if let outputHost, outputHost != originalHost {
            applyHost(outputHost, to: &rebuilt)
        }
        let originalPort = components?.port.map(String.init) ?? ""
        if let port = output["port"] as? String, port != originalPort {
            rebuilt.port = port.isEmpty ? nil : Int(port)
        }

        if let pathname = output["pathname"] as? String { rebuilt.percentEncodedPath = pathname }
        if let search = output["search"] as? String {
            let value = search.trimmingCharacters(in: CharacterSet(charactersIn: "?"))
            rebuilt.percentEncodedQuery = value.isEmpty ? nil : value
        }
        if let hash = output["hash"] as? String {
            let value = hash.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            rebuilt.percentEncodedFragment = value.isEmpty ? nil : value
        }
        guard let transformed = rebuilt.url else {
            throw JavaScriptURLTransformer.TransformError.invalidOutput
        }
        return transformed
    }

    private func applyHost(_ host: String, to components: inout URLComponents) {
        guard !host.isEmpty else {
            components.host = nil
            components.port = nil
            return
        }
        if let separator = host.lastIndex(of: ":"),
            !host.hasPrefix("["),
            let port = Int(host[host.index(after: separator)...])
        {
            components.host = String(host[..<separator])
            components.port = port
        } else if host.hasPrefix("["), let closing = host.firstIndex(of: "]") {
            components.host = String(host[host.index(after: host.startIndex)..<closing])
            let remainder = host[host.index(after: closing)...]
            if remainder.hasPrefix(":"), let port = Int(remainder.dropFirst()) {
                components.port = port
            }
        } else {
            components.host = host
        }
    }
}
