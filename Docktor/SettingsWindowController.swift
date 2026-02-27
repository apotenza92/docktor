import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(services: AppServices) {
        let view = PreferencesView(
            coordinator: services.coordinator,
            updateManager: services.updateManager,
            preferences: services.preferences
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Docktor Settings"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()

        super.init(window: window)

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            window.setContentSize(fittingSize)
            window.minSize = fittingSize
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
