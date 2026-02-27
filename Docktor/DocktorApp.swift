//
//  DocktorApp.swift
//  Docktor
//
//  Created by Alex on 27/12/2025.
//

import SwiftUI

@main
struct DocktorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppDelegate.services = .live
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
