//
//  NSFetchResults+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/6.
//

import Foundation
import SwiftUI

extension FetchedResults: Equatable where Result: Equatable {
    public static func == (lhs: FetchedResults, rhs: FetchedResults) -> Bool {
        Array(lhs) == Array(rhs)
    }
}
