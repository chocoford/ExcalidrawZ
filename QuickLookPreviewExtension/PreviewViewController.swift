//
//  PreviewViewController.swift
//  QuickLookPreviewExtension
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import QuickLook
import os.log
import WebKit
import Combine
import CoreData

import SwiftyAlert

class PreviewState: ObservableObject {
    @Published var file: ExcalidrawFile?
    @Published var error: Error?
}

#if canImport(AppKit)
import AppKit
import QuickLookUI
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
}

#elseif canImport(UIKit)
import UIKit

class PreviewViewController: UIViewController, QLPreviewingController {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PreviewViewController")
    /// Can not use `@StateObject` here
    var state = PreviewState()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.view = UIHostingController(
            rootView: QuickLookView(state: state)
                .swiftyAlert()
        ).view
    }
}
#endif

extension PreviewViewController {
    func preparePreviewOfSearchableItem(identifier: String, queryString: String?) async throws {
        // Implement this method and set QLSupportsSearchableItems to YES in the Info.plist of the extension if you support CoreSpotlight.

        // Perform any setup necessary in order to prepare the view.
        // Quick Look will display a loading spinner until this returns.
        
        // Can not use CoreData
        self.logger.info("[PreviewViewController] preparePreviewOfSearchableItem: \(identifier), \(queryString ?? "")")
        
//        let container = PersistenceController.shared.container
//        let uri = URL(string:identifier)!
//
//        do {
//            if let objectID = container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: uri) {
//                let file = try ExcalidrawFile(from: objectID, context: container.viewContext)
//                self.state.file = file
//            }
//        } catch {
//            self.state.error = error
//            self.logger.error("\(error)")
//        }
    }
    
    
    
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

//struct ImageView: View {
//    var image: Image
//    var body: some View {
//        image
//    }
//}
