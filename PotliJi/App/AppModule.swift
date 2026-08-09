import SwiftUI

@MainActor
protocol AppModule: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var isEnabled: Bool { get }

    func start()
    func stop()
    func settingsView() -> AnyView
}

@MainActor
final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    @Published private(set) var modules: [any AppModule] = []

    private init() {}

    func register(_ module: any AppModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        modules.append(module)
        if module.isEnabled { module.start() }
    }
}
