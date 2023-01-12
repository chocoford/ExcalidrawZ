//
//  Array+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/5.
//

import Foundation

extension Array {
    func safeSubscribe(at index: Self.Index) -> Self.Element? {
        if self.count == 0 {
            return nil
        }
        return self[Swift.max(0, Swift.min(index, self.count - 1))]
    }
}
