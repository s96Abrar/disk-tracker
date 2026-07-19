//
//  DiskTrackerApp.swift
//  DiskTracker
//

import SwiftUI

@main
struct DiskTrackerApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .windowResizability(.contentSize)
    }
}
