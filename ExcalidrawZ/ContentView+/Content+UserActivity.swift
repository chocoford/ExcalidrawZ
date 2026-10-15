//
//  Content+UserActivity.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/25/25.
//

import SwiftUI
import CoreData
import SwiftyAlert
import CoreSpotlight
import Logging

extension Notification.Name {
    static let onContinueUserSearchableItemAction = Notification.Name("OnContinueUserSearchableItemAction")
    static let onContinueUserQueryContinuationAction = Notification.Name("OnContinueUserQueryContinuationAction")
}

struct UserActivityHandlerModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    
    let logger = Logger(label: "UserActivityHandlerModifier")
    
    func body(content: Content) -> some View {
        content
            .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                self.logger.debug("[UserActivityHandlerModifier] onContinueUserActivity(CSSearchableItemActionType)")
                self.handleUserSearchableItemAction(userActivity: userActivity)
            }
            .onContinueUserActivity(CSQueryContinuationActionType) { userActivity in
                self.logger.debug("[UserActivityHandlerModifier] onContinueUserActivity(CSQueryContinuationActionType)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .onContinueUserSearchableItemAction)) { notification in
                if let userActivity = notification.object as? NSUserActivity {
                    handleUserSearchableItemAction(userActivity: userActivity)
                }
            }
    }
    
    
    private func handleUserSearchableItemAction(userActivity: NSUserActivity) {
        guard let userinfo = userActivity.userInfo as? [String : Any] else { return }
        let identifier = userinfo["kCSSearchableItemActivityIdentifier"] as? String ?? ""

        if let fileID = UUID(uuidString: identifier),
           let file = try? PersistenceController.shared.findFile(id: fileID),
           !file.inTrash {
            fileState.setActiveFile(.file(file))
            return
        }

        guard let uri = URL(string: identifier) else { return }
        let container = PersistenceController.shared.container
        if let objectID = container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: uri) {
            let object = viewContext.object(with: objectID)
            
            if case let file as File = object,
               !file.inTrash {
                fileState.setActiveFile(.file(file))
            }
        }
            
        
        
    }
}
