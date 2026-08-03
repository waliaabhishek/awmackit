import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    let settingsStore: SettingsStore
    let browserCatalog: BrowserCatalog
    let historyStore: HistoryStore
    let routingLogger: RoutingLogger
    let promptController: BrowserPromptController
    let pasteboardMonitor: PasteboardMonitor

    lazy var launcher = BrowserLauncher(browserCatalog: browserCatalog)
    lazy var router = LinkRouterCoordinator(
        settingsStore: settingsStore,
        browserCatalog: browserCatalog,
        launcher: launcher,
        historyStore: historyStore,
        logger: routingLogger,
        promptController: promptController
    )
    lazy var linkRouterModule = LinkRouterModule(environment: self)

    private init() {
        settingsStore = SettingsStore()
        browserCatalog = BrowserCatalog()
        historyStore = HistoryStore()
        routingLogger = RoutingLogger()
        promptController = BrowserPromptController()
        pasteboardMonitor = PasteboardMonitor()
    }

    func start() async {
        async let loadSettings: Void = settingsStore.loadIfNeeded()
        async let refreshCatalog: Void = browserCatalog.refresh()
        async let loadHistory: Void = historyStore.loadIfNeeded()
        _ = await (loadSettings, refreshCatalog, loadHistory)

        ModuleRegistry.shared.register(linkRouterModule)
        pasteboardMonitor.configure(environment: self)
        pasteboardMonitor.startIfNeeded()
    }
}
