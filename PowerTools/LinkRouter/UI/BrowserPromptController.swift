import AppKit
import Combine
import LinkRouterCore
import SwiftUI

struct PromptSelection {
    let target: RouteTarget
    let openInBackground: Bool
    let openInNewWindow: Bool
    let createDomainRule: Bool
}

@MainActor
final class BrowserPromptController {
    private struct PendingPrompt {
        let url: URL
        let targets: [RouteTarget]
        let presentation: [BrowserPresentation]
        let showsURL: Bool
        let allowActions: Bool
        let controlOpensInBackground: Bool
        let preservePosition: Bool
        let continuation: CheckedContinuation<PromptSelection?, Never>
    }

    private var panel: BrowserPromptPanel?
    private var continuation: CheckedContinuation<PromptSelection?, Never>?
    private var pendingPrompts: [PendingPrompt] = []
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var preservesPosition = false

    private static let promptOriginKey = "PowerTools.LinkRouter.PromptOrigin"

    func choose(
        url: URL,
        targets: [RouteTarget],
        presentation: [BrowserPresentation],
        showsURL: Bool,
        allowActions: Bool,
        controlOpensInBackground: Bool,
        preservePosition: Bool
    ) async -> PromptSelection? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<PromptSelection?, Never>) in
            pendingPrompts.append(
                PendingPrompt(
                    url: url,
                    targets: targets,
                    presentation: presentation,
                    showsURL: showsURL,
                    allowActions: allowActions,
                    controlOpensInBackground: controlOpensInBackground,
                    preservePosition: preservePosition,
                    continuation: continuation
                ))
            presentNextIfNeeded()
        }
    }

    private func presentNextIfNeeded() {
        guard continuation == nil, panel == nil, !pendingPrompts.isEmpty else { return }
        let request = pendingPrompts.removeFirst()
        continuation = request.continuation
        let shortcutByID: [String: String] = Dictionary(
            uniqueKeysWithValues: request.presentation.compactMap { item -> (String, String)? in
                guard let shortcut = item.promptShortcut?.lowercased(), !shortcut.isEmpty else { return nil }
                return (item.id, shortcut)
            }
        )
        let model = BrowserPromptViewModel(
            url: request.url,
            targets: request.targets,
            shortcutByID: shortcutByID,
            showsURL: request.showsURL,
            allowActions: request.allowActions,
            controlOpensInBackground: request.controlOpensInBackground,
            iconProvider: { AppEnvironment.shared.browserCatalog.icon(for: $0) },
            completion: { [weak self] selection in self?.dismiss(result: selection) },
            cancellation: { [weak self] in self?.dismiss(result: nil) }
        )
        present(model, preservePosition: request.preservePosition)
    }

    private func present(_ model: BrowserPromptViewModel, preservePosition: Bool) {
        let width = min(max(CGFloat(model.targets.count) * 104 + 48, 380), 920)
        let height: CGFloat = model.showsURL ? 190 : 150
        let contentSize = NSSize(width: width, height: height)
        let panel = BrowserPromptPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.title = "Choose a Browser"
        panel.identifier = NSUserInterfaceItemIdentifier("PowerTools.BrowserPrompt")

        let hostingController = NSHostingController(
            rootView: BrowserPromptView(model: model)
                .frame(width: contentSize.width, height: contentSize.height)
        )
        // NSHostingController's automatic sizing collapses a horizontal ScrollView
        // to its minimum intrinsic width on recent macOS releases. The picker panel
        // owns its size, so prevent the hosted view from renegotiating the window.
        hostingController.sizingOptions = []
        hostingController.view.frame = NSRect(origin: .zero, size: contentSize)
        hostingController.view.autoresizingMask = [.width, .height]
        panel.contentViewController = hostingController
        panel.contentMinSize = contentSize
        panel.contentMaxSize = contentSize
        panel.setContentSize(contentSize)
        preservesPosition = preservePosition
        position(panel, preservePosition: preservePosition)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            model?.handleKeyDown(event) == true ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak model] event in
            model?.modifierFlagsChanged(event.modifierFlags)
            return event
        }
    }

    private func position(_ panel: NSPanel, preservePosition: Bool) {
        if preservePosition,
            let stored = UserDefaults.standard.dictionary(forKey: Self.promptOriginKey),
            let x = stored["x"] as? Double,
            let y = stored["y"] as? Double
        {
            let storedOrigin = NSPoint(x: x, y: y)
            if let screen = NSScreen.screens.first(where: {
                $0.visibleFrame.insetBy(dx: 12, dy: 12).contains(storedOrigin)
            }) {
                panel.setFrameOrigin(clampedOrigin(storedOrigin, panel: panel, visibleFrame: screen.visibleFrame))
                return
            }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { panel.center(); return }
        var origin = NSPoint(
            x: mouse.x - panel.frame.width / 2,
            y: mouse.y - panel.frame.height - 18
        )
        if origin.y < visibleFrame.minY + 12 {
            origin.y = min(mouse.y + 18, visibleFrame.maxY - panel.frame.height - 12)
        }
        panel.setFrameOrigin(clampedOrigin(origin, panel: panel, visibleFrame: visibleFrame))
    }

    private func clampedOrigin(_ origin: NSPoint, panel: NSPanel, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - panel.frame.width - 12),
            y: min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - panel.frame.height - 12)
        )
    }

    private func dismiss(result: PromptSelection?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
        if preservesPosition, let panel {
            UserDefaults.standard.set(
                ["x": Double(panel.frame.origin.x), "y": Double(panel.frame.origin.y)],
                forKey: Self.promptOriginKey
            )
        }
        panel?.orderOut(nil)
        panel = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
        presentNextIfNeeded()
    }
}

private final class BrowserPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        super.cancelOperation(sender)
    }
}

@MainActor
private final class BrowserPromptViewModel: ObservableObject {
    let url: URL
    let targets: [RouteTarget]
    let shortcutByID: [String: String]
    let showsURL: Bool
    let allowActions: Bool
    let controlOpensInBackground: Bool
    let iconProvider: (RouteTarget) -> NSImage
    let completion: (PromptSelection) -> Void
    let cancellation: () -> Void

    @Published var selectedIndex = 0
    @Published var showActions = false
    private var shiftCopyWorkItem: DispatchWorkItem?

    init(
        url: URL,
        targets: [RouteTarget],
        shortcutByID: [String: String],
        showsURL: Bool,
        allowActions: Bool,
        controlOpensInBackground: Bool,
        iconProvider: @escaping (RouteTarget) -> NSImage,
        completion: @escaping (PromptSelection) -> Void,
        cancellation: @escaping () -> Void
    ) {
        self.url = url
        self.targets = targets
        self.shortcutByID = shortcutByID
        self.showsURL = showsURL
        self.allowActions = allowActions
        self.controlOpensInBackground = controlOpensInBackground
        self.iconProvider = iconProvider
        self.completion = completion
        self.cancellation = cancellation
        self.showActions = allowActions && NSEvent.modifierFlags.contains(.option)
    }

    func select(_ target: RouteTarget, newWindow: Bool = false, createRule: Bool = false) {
        completion(
            PromptSelection(
                target: target,
                openInBackground: controlOpensInBackground && NSEvent.modifierFlags.contains(.control),
                openInNewWindow: newWindow,
                createDomainRule: createRule || NSEvent.modifierFlags.contains(.command)
            ))
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !targets.isEmpty else {
            if event.keyCode == 53 { cancellation(); return true }
            return false
        }

        switch event.keyCode {
        case 53:  // Escape
            cancellation()
            return true
        case 36, 49:  // Return / Space
            select(targets[selectedIndex])
            return true
        case 123:  // Left
            selectedIndex = (selectedIndex - 1 + targets.count) % targets.count
            return true
        case 124:  // Right
            selectedIndex = (selectedIndex + 1) % targets.count
            return true
        case 48:  // Tab
            let delta = event.modifierFlags.contains(.shift) ? -1 : 1
            selectedIndex = (selectedIndex + delta + targets.count) % targets.count
            return true
        default:
            break
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            select(.copyURL)
            return true
        }
        if event.modifierFlags.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "c" {
            select(.copyURL)
            return true
        }

        if let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 {
            if let index = targets.firstIndex(where: { shortcutByID[$0.id] == key }) {
                selectedIndex = index
                select(targets[index])
                return true
            }
            if let number = Int(key), number >= 1, number <= targets.count {
                selectedIndex = number - 1
                select(targets[number - 1])
                return true
            }
        }
        return false
    }

    func modifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        showActions = allowActions && flags.contains(.option)
        shiftCopyWorkItem?.cancel()

        // Velja's prompt supports tapping Shift as a quick-copy gesture. Delay the
        // action briefly so Shift+Option+Tab can still be used for reverse cycling.
        let meaningfulFlags = flags.intersection(.deviceIndependentFlagsMask)
        guard meaningfulFlags == [.shift] else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let currentFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard currentFlags == [.shift] else { return }
            self.select(.copyURL)
        }
        shiftCopyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }
}

private struct BrowserPromptView: View {
    @ObservedObject var model: BrowserPromptViewModel

    var body: some View {
        VStack(spacing: 12) {
            if model.showsURL {
                VStack(spacing: 2) {
                    Text(model.url.host ?? model.url.absoluteString)
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.targets.enumerated()), id: \.element.id) { index, target in
                        targetButton(target, index: index)
                    }
                    if model.showActions {
                        targetButton(.copyURL, index: -1)
                        targetButton(.share, index: -1)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        }
        .padding(2)
    }

    private func targetButton(_ target: RouteTarget, index: Int) -> some View {
        Button {
            model.select(target)
        } label: {
            VStack(spacing: 7) {
                Image(nsImage: icon(for: target))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 42, height: 42)
                Text(target.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 84, height: 30)
                if let shortcut = shortcutLabel(target: target, index: index) {
                    Text(shortcut)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(index == model.selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if target.kind == .application || target.kind == .browserProfile || target.kind == .browserPWA {
                Button("Open in New Window") { model.select(target, newWindow: true) }
                Button("Always Use for This Domain") { model.select(target, createRule: true) }
            }
        }
        .help("Control-click opens in the background. Command-click creates a domain rule.")
    }

    private func icon(for target: RouteTarget) -> NSImage {
        switch target.kind {
        case .copyURL:
            NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy URL") ?? NSImage()
        case .share:
            NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share") ?? NSImage()
        default:
            model.iconProvider(target)
        }
    }

    private func shortcutLabel(target: RouteTarget, index: Int) -> String? {
        if let shortcut = model.shortcutByID[target.id] { return shortcut.uppercased() }
        guard index >= 0, index < 9 else { return nil }
        return String(index + 1)
    }
}
