//
//  String+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/5.
//

import Foundation

extension String {
    init?<S: StringProtocol>(_ from: S?) {
        guard let from = from else {
            return nil
        }
        self = String(from)
    }
}
