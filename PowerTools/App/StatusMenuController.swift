import AppKit
import Combine
import LinkRouterCore

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private unowned let environment: AppEnvironment
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private let menu = NSMenu()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        menu.delegate = self
    }

    func start() {
        environment.settingsStore.$settings
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.reconcileStatusItem()
                }
            }
            .store(in: &cancellables)
        environment.browserCatalog.$browsers
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateButtonAppearance() }
            }
            .store(in: &cancellables)
        environment.browserCatalog.$profiles
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateButtonAppearance() }
            }
            .store(in: &cancellables)
        reconcileStatusItem()
    }

    func temporarilyReveal(seconds: TimeInterval = 5) {
        ensureStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.reconcileStatusItem()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func reconcileStatusItem(using settings: LinkRouterSettings? = nil) {
        let settings = settings ?? environment.settingsStore.settings.linkRouter
        if settings.showMenuBarIcon {
            ensureStatusItem(using: settings)
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        updateButtonAppearance(using: settings)
    }

    private func ensureStatusItem(using settings: LinkRouterSettings? = nil) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        item.button?.toolTip = "Power Tools — Link Router"
        statusItem = item
        updateButtonAppearance(using: settings)
    }

    private func updateButtonAppearance(using settings: LinkRouterSettings? = nil) {
        guard let button = statusItem?.button else { return }
        let settings = settings ?? environment.settingsStore.settings.linkRouter
        switch settings.menuBarIconStyle {
        case .activeBrowser:
            let target = resolvePrimaryTarget(settings.primaryTarget)
            let image =
                (environment.browserCatalog.icon(for: target).copy() as? NSImage)
                ?? environment.browserCatalog.icon(for: target)
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            button.image = image
        case .link:
            button.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Link Router")
            button.image?.isTemplate = true
        case .compass:
            button.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "Link Router")
            button.image?.isTemplate = true
        case .arrowTurn:
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Link Router")
            button.image?.isTemplate = true
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let settings = environment.settingsStore.settings.linkRouter

        let enabled = NSMenuItem(
            title: "Automatic Routing Enabled",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabled.target = self
        enabled.state = settings.isEnabled ? .on : .off
        menu.addItem(enabled)

        let isDefaultBrowser = DefaultBrowserManager().isPowerToolsDefaultBrowser
        let defaultItem = NSMenuItem(
            title: isDefaultBrowser ? "Power Tools Is the Default Browser" : "Use Power Tools as Default Browser",
            action: isDefaultBrowser ? nil : #selector(makeDefaultBrowser(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = isDefaultBrowser ? nil : self
        defaultItem.state = isDefaultBrowser ? .on : .off
        defaultItem.isEnabled = !isDefaultBrowser
        menu.addItem(defaultItem)
        menu.addItem(.separator())

        menu.addItem(
            browserSubmenu(
                title: "Primary Browser",
                selected: settings.primaryTarget,
                action: #selector(selectPrimaryTarget(_:))
            ))
        let pickerHint = NSMenuItem(
            title: browserPickerHint(settings.browserPickerModifier),
            action: nil,
            keyEquivalent: ""
        )
        pickerHint.isEnabled = false
        menu.addItem(pickerHint)

        menu.addItem(.separator())
        let openClipboard = NSMenuItem(
            title: "Open URL from Clipboard", action: #selector(openClipboardURL(_:)), keyEquivalent: "o")
        openClipboard.keyEquivalentModifierMask = [.command, .shift]
        openClipboard.target = self
        menu.addItem(openClipboard)

        let cleanClipboard = NSMenuItem(
            title: "Clean and Copy URL from Clipboard", action: #selector(cleanClipboardURL(_:)), keyEquivalent: "c")
        cleanClipboard.keyEquivalentModifierMask = [.command, .shift]
        cleanClipboard.target = self
        menu.addItem(cleanClipboard)

        let songlink = NSMenuItem(
            title: "Copy Songlink for Clipboard URL", action: #selector(copySonglink(_:)), keyEquivalent: "")
        songlink.target = self
        menu.addItem(songlink)

        menu.addItem(.separator())
        let history = NSMenuItem(title: "History…", action: #selector(showHistory(_:)), keyEquivalent: "h")
        history.keyEquivalentModifierMask = [.command]
        history.target = self
        menu.addItem(history)

        let log = NSMenuItem(title: "Routing Log…", action: #selector(showLog(_:)), keyEquivalent: "l")
        log.keyEquivalentModifierMask = [.command, .option]
        log.target = self
        menu.addItem(log)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Power Tools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func browserSubmenu(title: String, selected: RouteTarget, action: Selector) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let prompt = targetMenuItem(.prompt, selected: selected, action: action, index: nil)
        submenu.addItem(prompt)
        submenu.addItem(.separator())

        for (index, target) in environment.browserCatalog.allTargets.enumerated() {
            submenu.addItem(
                targetMenuItem(target, selected: selected, action: action, index: index < 9 ? index + 1 : nil))
        }
        root.submenu = submenu
        return root
    }

    private func targetMenuItem(_ target: RouteTarget, selected: RouteTarget, action: Selector, index: Int?)
        -> NSMenuItem
    {
        let item = NSMenuItem(title: target.displayName, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = target.id
        item.state = target.id == selected.id ? .on : .off
        if let index {
            item.keyEquivalent = String(index)
            item.keyEquivalentModifierMask = [.option]
        }
        if target.kind != .prompt {
            let image =
                (environment.browserCatalog.icon(for: target).copy() as? NSImage)
                ?? environment.browserCatalog.icon(for: target)
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }
        return item
    }

    private func target(id: String) -> RouteTarget? {
        if id == RouteTarget.prompt.id { return .prompt }
        return environment.browserCatalog.target(withID: id)
    }

    private func resolvePrimaryTarget(_ target: RouteTarget) -> RouteTarget {
        switch target.kind {
        case .prompt, .primaryBrowser, .alternativeBrowser, .systemDefault:
            return environment.browserCatalog.browsers.first?.routeTarget ?? .prompt
        default:
            return target
        }
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        environment.settingsStore.settings.linkRouter.isEnabled.toggle()
    }

    @objc private func makeDefaultBrowser(_ sender: Any?) {
        Task { @MainActor in
            do {
                let manager = DefaultBrowserManager()
                guard !manager.isPowerToolsDefaultBrowser else { return }
                try await manager.setPowerToolsAsDefaultBrowser()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func selectPrimaryTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let target = target(id: id) else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            launch(target)
        } else {
            environment.settingsStore.settings.linkRouter.primaryTarget = target
        }
    }

    @objc private func openClipboardURL(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        let urls = PowerToolsServices.extractURLs(from: value)
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        environment.router.handleIncoming(urls, trigger: .clipboard)
    }

    private func browserPickerHint(_ modifier: BrowserPickerModifier) -> String {
        guard modifier != .disabled else { return "Browser Picker Modifier Disabled" }
        return "Hold \(modifier.displayName) to Choose a Browser"
    }

    @objc private func cleanClipboardURL(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string),
            let url = PowerToolsServices.extractURLs(from: value).first
        else {
            NSSound.beep()
            return
        }
        environment.router.copySanitizedURL(url)
    }

    @objc private func copySonglink(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string),
            let url = PowerToolsServices.extractURLs(from: value).first
        else {
            NSSound.beep()
            return
        }
        let cleanSettings = environment.settingsStore.settings.linkRouter
        let sanitizer = URLSanitizer(
            additionalParameters: Set(cleanSettings.additionalTrackingParameters),
            allowedParameters: Set(cleanSettings.allowedTrackingParameters),
            removeTrackingParameters: cleanSettings.removeTrackingParameters,
            unwrapRedirects: cleanSettings.unwrapEmbeddedRedirects
        )
        let clean = sanitizer.sanitize(url).url.absoluteString
        let embedded =
            clean
            .replacingOccurrences(of: "https:", with: "https%3A", options: [.anchored])
            .replacingOccurrences(of: "http:", with: "http%3A", options: [.anchored])
        guard let songlink = URL(string: "https://song.link/\(embedded)") else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(songlink.absoluteString, forType: .string)
    }

    @objc private func showHistory(_ sender: Any?) { WindowPresenter.shared.showHistory() }
    @objc private func showLog(_ sender: Any?) { WindowPresenter.shared.showRoutingLog() }
    @objc private func showSettings(_ sender: Any?) { WindowPresenter.shared.showSettings() }

    private func launch(_ target: RouteTarget) {
        guard target.kind != .prompt, let blankPage = URL(string: "about:blank") else { return }
        Task {
            do {
                try await environment.launcher.open(
                    urls: [blankPage],
                    target: target,
                    inBackground: false,
                    newWindow: false
                )
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
