//
//  llmt2App.swift
//  llmt2
//
//  Created by Seth Paonessa on 9/6/25.
//

import SwiftUI

@main
struct llmt2App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    print("🚀 LLMT2 App starting up...")
                    print("📱 Running on macOS")
                    #if os(macOS)
                    print("🍎 macOS detected")
                    #endif
                }
        }
    }
}
