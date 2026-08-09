import AppKit

@MainActor
final class SharePresenter {
    static let shared = SharePresenter()

    private var panel: NSPanel?
    private var picker: NSSharingServicePicker?

    func present(items: [Any]) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let picker = NSSharingServicePicker(items: items)
        guard let view = panel.contentView else { return }
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        self.panel = panel
        self.picker = picker

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.picker = nil
        }
    }
}
