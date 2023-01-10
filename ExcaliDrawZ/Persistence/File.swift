//
//  File.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/9.
//

import Foundation

extension File {
    func updateElements(with elementsData: Data) throws {
        guard let data = self.content else { return }
        var obj = try JSONSerialization.jsonObject(with: data) as! [String : Any]
        let elements = try JSONSerialization.jsonObject(with: elementsData)
        obj["elements"] = elements
        self.content = try JSONSerialization.data(withJSONObject: obj)
        self.updatedAt = .now
    }
}

#if DEBUG
extension File {
    static let preview = {
        let file = File(context: PersistenceController.preview.container.viewContext)
        file.id = UUID()
        file.name = "preview"
        file.createdAt = .now
        file.group = Group.preview
        return file
    }()
}
#endif
