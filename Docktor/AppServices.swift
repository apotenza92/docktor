import Foundation

@MainActor
final class AppServices {
    static let live = AppServices(
        preferences: Preferences.shared,
        coordinator: DockExposeCoordinator.shared,
        updateManager: UpdateManager.shared
    )

    let preferences: Preferences
    let coordinator: DockExposeCoordinator
    let updateManager: UpdateManager

    init(preferences: Preferences,
         coordinator: DockExposeCoordinator,
         updateManager: UpdateManager) {
        self.preferences = preferences
        self.coordinator = coordinator
        self.updateManager = updateManager
    }
}
