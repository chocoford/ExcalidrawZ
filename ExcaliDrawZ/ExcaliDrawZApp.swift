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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 900, height: 500)
    }
}
