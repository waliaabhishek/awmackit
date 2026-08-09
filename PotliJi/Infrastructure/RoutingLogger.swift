import Combine
import Foundation

struct RoutingLogEntry: Identifiable, Hashable, Sendable {
    enum Level: String, Sendable {
        case info
        case warning
        case error
        case debug
    }

    var id = UUID()
    var timestamp = Date()
    var level: Level
    var stage: String
    var message: String
}

@MainActor
final class RoutingLogger: ObservableObject {
    @Published private(set) var entries: [RoutingLogEntry] = []
    var maximumEntries = 1_000
    var isEnabled = true

    func log(_ level: RoutingLogEntry.Level = .info, stage: String, _ message: String) {
        guard isEnabled else { return }
        entries.insert(RoutingLogEntry(level: level, stage: stage, message: message), at: 0)
        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
