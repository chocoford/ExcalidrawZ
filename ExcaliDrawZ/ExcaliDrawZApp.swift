//
//  ExcaliDrawZApp.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI

@main
@MainActor
struct ExcaliDrawZApp: App {
    let store = AppStore(state: AppState(),
                         reducer: appReducer,
                         environment: AppEnvironment())
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 500)
        #endif
    }
}
