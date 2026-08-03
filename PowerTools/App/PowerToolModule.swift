import SwiftUI

@MainActor
protocol PowerToolModule: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var isEnabled: Bool { get set }

    func start()
    func stop()
    func settingsView() -> AnyView
}

@MainActor
final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    @Published private(set) var modules: [any PowerToolModule] = []

    private init() {}

    func register(_ module: any PowerToolModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        modules.append(module)
        if module.isEnabled { module.start() }
    }
}
