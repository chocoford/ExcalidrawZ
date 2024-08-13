//
//  CoreDataClient.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/14.
//

import Foundation
import CoreData

//struct CoreDataClient {
//    var provider: PersistenceController
//    var container: NSPersistentContainer
//    var viewContext: NSManagedObjectContext
//    var newBackgroundContext: NSManagedObjectContext
////    var saveShow: (_ show: Show, _ context: NSManagedObjectContext?) -> Void
////    var fetchedShows: [ShowEntity]
//}
//
//extension CoreDataClient: DependencyKey {
//    static var liveValue: Self {
//        .init(provider: PersistenceController.shared,
//              container: PersistenceController.shared.container,
//              viewContext: PersistenceController.shared.container.viewContext,
//              newBackgroundContext: PersistenceController.shared.container.newBackgroundContext())
//    }
//}
//
//
//extension DependencyValues {
//    var coreData: CoreDataClient {
//        get { self[CoreDataClient.self] }
//        set { self[CoreDataClient.self] = newValue }
//    }
//}
