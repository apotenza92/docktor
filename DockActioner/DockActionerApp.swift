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
        Settings {
            PreferencesView(coordinator: DockExposeCoordinator.shared)
                .frame(minWidth: 560, idealWidth: 560)
        }
    }
}
