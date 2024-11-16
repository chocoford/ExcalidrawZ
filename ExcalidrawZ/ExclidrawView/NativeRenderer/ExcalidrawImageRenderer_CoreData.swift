//
//  ExcalidrawImageRenderer.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI

func renderExcalidrawImage(
    context: GraphicsContext,
    fileID: String,
    file: ExcalidrawFile,
    rect: CGRect
) {
    var file = file
    do {
        try file.syncFiles(context: PersistenceController.shared.container.viewContext)
    } catch {
        print(error)
    }
    if let base64String = file.files[fileID]?.dataURL,
       let commaIndex = base64String.firstIndex(of: ",") {
        if let data = Data(base64Encoded: String(base64String.suffix(from: base64String.index(after: commaIndex)))),
           let image = Image(data: data) {
            context.draw(
                context.resolve(image),
                in: rect
            )
        }
    }
}
