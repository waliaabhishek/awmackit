import AppKit
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private var didBeginProcessing = false

    override func loadView() {
        let label = NSTextField(labelWithString: "Sending links to Power Tools…")
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.startAnimation(nil)

        let stack = NSStackView(views: [progress, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        view = stack
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didBeginProcessing else { return }
        didBeginProcessing = true
        let controller = WeakShareViewController(self)
        collectURLs { urls in
            DispatchQueue.main.async {
                controller.value?.sendToPowerTools(urls)
            }
        }
    }

    private func collectURLs(completion: @escaping @Sendable ([URL]) -> Void) {
        let providers =
            extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        let group = DispatchGroup()
        let collected = LockedURLCollection()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let url: URL?
                    if let value = item as? URL {
                        url = value
                    } else if let value = item as? NSURL {
                        url = value as URL
                    } else if let value = item as? String {
                        url = URL(string: value)
                    } else {
                        url = nil
                    }
                    if let url, Self.isWebURL(url) {
                        collected.append([url])
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    guard let text = item as? String else { return }
                    let urls = Self.extractURLs(from: text)
                    collected.append(urls)
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            var seen = Set<String>()
            let unique = collected.snapshot().filter { seen.insert($0.absoluteString).inserted }
            completion(unique)
        }
    }

    private func sendToPowerTools(_ urls: [URL]) {
        guard !urls.isEmpty else {
            cancel(message: "The shared content does not contain a web URL.")
            return
        }
        var components = URLComponents()
        components.scheme = "powertools-link"
        components.host = "open"
        components.queryItems =
            [URLQueryItem(name: "source", value: "share-extension")]
            + urls.map { URLQueryItem(name: "url", value: $0.absoluteString) }
        guard let commandURL = components.url else {
            cancel(message: "Power Tools could not create a routing command.")
            return
        }

        let controller = WeakShareViewController(self)
        extensionContext?.open(commandURL) { succeeded in
            DispatchQueue.main.async {
                if succeeded {
                    controller.value?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                } else {
                    controller.value?.cancel(
                        message: "Power Tools could not be opened. Launch the main app once and try again."
                    )
                }
            }
        }
    }

    private func cancel(message: String) {
        let error = NSError(
            domain: "PowerToolsShareExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        extensionContext?.cancelRequest(withError: error)
    }

    private nonisolated static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private nonisolated static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .filter(isWebURL)
    }
}

private final class LockedURLCollection: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ newURLs: [URL]) {
        lock.withLock {
            urls.append(contentsOf: newURLs)
        }
    }

    func snapshot() -> [URL] {
        lock.withLock { urls }
    }
}

private final class WeakShareViewController: @unchecked Sendable {
    weak var value: ShareViewController?

    init(_ value: ShareViewController) {
        self.value = value
    }
}
