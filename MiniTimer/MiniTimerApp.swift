//
//  MiniTimerApp.swift
//  MiniTimer
//
//  Created by Sameer Bajaj on 3/11/26.
//

import SwiftUI

@main
struct MiniTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 280, minHeight: 180)
        }
        .defaultSize(width: 360, height: 220)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .miniTimerCheckForUpdates, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let miniTimerCheckForUpdates = Notification.Name("miniTimerCheckForUpdates")
}
