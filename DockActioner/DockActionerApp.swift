//
//  DockActionerApp.swift
//  DockActioner
//
//  Created by Alex on 27/12/2025.
//

import SwiftUI
import AppKit

@main
struct DockActionerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            PreferencesView(coordinator: DockExposeCoordinator.shared)
        }
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
