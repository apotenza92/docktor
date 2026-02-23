//
//  DockterApp.swift
//  Dockter
//
//  Created by Alex on 27/12/2025.
//

import SwiftUI
import AppKit

@main
struct DockterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updateManager = UpdateManager.shared

    var body: some Scene {
        Settings {
            PreferencesView(coordinator: DockExposeCoordinator.shared,
                            updateManager: updateManager)
        }
    }
}
