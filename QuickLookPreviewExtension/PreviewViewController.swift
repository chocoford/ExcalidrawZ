//
//  PreviewViewController.swift
//  QuickLookPreviewExtension
//
//  Created by Dove Zachary on 2024/10/8.
//

import AppKit
import QuickLookUI
import SwiftUI
import os.log
import WebKit
import Combine

import SwiftyAlert

class PreviewState: ObservableObject {
    @Published var file: ExcalidrawFile?
    @Published var error: Error?
}

class PreviewViewController: NSViewController, QLPreviewingController {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PreviewViewController")
    /// Can not use `@StateObject` here
    var state = PreviewState()
    override func loadView() {
        super.loadView()
        // Do any additional setup after loading the view.
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view = NSHostingView(
            rootView: QuickLookView(state: state)
                .swiftyAlert()
        )
    }

    /*
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.

        // Perform any setup necessary in order to prepare the view.
        // Quick Look will display a loading spinner until this returns.
    }
    */
    
    
    // Operation not permitted
    // let server = ExcalidrawServer(autoStart: false)
    
    func preparePreviewOfFile(at url: URL) async throws {
        // Add the supported content types to the QLSupportedContentTypes array in the Info.plist of the extension.

        // Perform any setup necessary in order to prepare the view.

        // Quick Look will display a loading spinner until this returns.
        do {
            let file = try ExcalidrawFile(contentsOf: url)
            self.state.file = file
        } catch {
            self.state.error = error
        }
    }

}

#if canImport(AppKit)
#elseif canImport(UIKit)
import UIKit

class PreviewViewController: UIViewController, QLPreviewingController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    /*
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.

        // Perform any setup necessary in order to prepare the view.
        // Quick Look will display a loading spinner until this returns.
    }
    */

    func preparePreviewOfFile(at url: URL) async throws {
        // Add the supported content types to the QLSupportedContentTypes array in the Info.plist of the extension.

        // Perform any setup necessary in order to prepare the view.

        // Quick Look will display a loading spinner until this returns.
    }

}
#endif

//struct ImageView: View {
//    var image: Image
//    var body: some View {
//        image
//    }
//}
