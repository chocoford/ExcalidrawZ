//
//  CheckForUpdatesView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/1.
//

#if os(macOS)
import SwiftUI
import Sparkle

// This is the view for the Check for Updates menu item
// Note this intermediate view is necessary for the disabled state on the menu item to work properly before Monterey.
// See https://stackoverflow.com/questions/68553092/menu-not-updating-swiftui-bug for more info
struct CheckForUpdatesView: View {
    @ObservedObject var checkForUpdatesViewModel: UpdateChecker
    
    init(checkForUpdatesViewModel: UpdateChecker) {
        self.checkForUpdatesViewModel = checkForUpdatesViewModel
    }
    
    var body: some View {
        Button(.localizable(.updatesCheckButton)) {
            checkForUpdatesViewModel.updater?.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
#endif
