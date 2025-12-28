//
//  DockAppExposeApp.swift
//  DockAppExpose
//
//  Created by Alex on 27/12/2025.
//

import SwiftUI
import AppKit

@main
struct DockAppExposeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            PreferencesView(coordinator: DockExposeCoordinator.shared)
        }
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
