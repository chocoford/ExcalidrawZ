//
//  FileProvider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/22/25.
//

import SwiftUI
import CoreData

struct FileProvider: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    var objectID: NSManagedObjectID
    var content: (FileState.ActiveFile) -> AnyView
    
    init<Content: View>(
        objectID: NSManagedObjectID,
        @ViewBuilder content: @escaping (FileState.ActiveFile) -> Content
    ) {
        self.objectID = objectID
        self.content = { file in
            AnyView(content(file))
        }
    }
    
    @State private var file: FileState.ActiveFile?
    
    var body: some View {
        ZStack {
            if let file {
                content(file)
            }
        }
        .task {
            let object = viewContext.object(with: objectID)
            
            if let file = object as? File {
                self.file = .file(file)
            } else if let file = object as? CollaborationFile {
                self.file = .collaborationFile(file)
            }
        }
    }
}


