import AppIntents
import LinkRouterCore

struct BrowserTargetEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Browser or Profile")
    static let defaultQuery = BrowserTargetEntityQuery()

    let id: String
    let name: String
    let detail: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: detail.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    init(target: RouteTarget) {
        id = target.id
        name = target.displayName
        switch target.kind {
        case .browserProfile:
            detail = "Browser profile"
        case .browserPWA:
            detail = "Installed web app"
        case .application:
            detail = target.openMode == .privateWindow ? "Private window" : "Browser"
        default:
            detail = nil
        }
    }
}

struct BrowserTargetEntityQuery: EntityQuery {
    func entities(for identifiers: [BrowserTargetEntity.ID]) async throws -> [BrowserTargetEntity] {
        await AppEnvironment.shared.browserCatalog.loadIfNeeded()
        return await MainActor.run {
            let catalog = AppEnvironment.shared.browserCatalog
            return identifiers.compactMap(catalog.target(withID:)).map(BrowserTargetEntity.init(target:))
        }
    }

    func suggestedEntities() async throws -> [BrowserTargetEntity] {
        await AppEnvironment.shared.browserCatalog.loadIfNeeded()
        return await MainActor.run {
            AppEnvironment.shared.browserCatalog.allTargets.map(BrowserTargetEntity.init(target:))
        }
    }

    func defaultResult() async -> BrowserTargetEntity? {
        await AppEnvironment.shared.settingsStore.loadIfNeeded()
        await AppEnvironment.shared.browserCatalog.loadIfNeeded()
        return await MainActor.run {
            let environment = AppEnvironment.shared
            let configured = environment.settingsStore.settings.linkRouter.primaryTarget
            let target: RouteTarget?
            switch configured.kind {
            case .application, .browserProfile, .browserPWA:
                target = configured
            default:
                target = environment.browserCatalog.normalTargets.first
            }
            return target.map(BrowserTargetEntity.init(target:))
        }
    }
}
