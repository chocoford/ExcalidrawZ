//
//  NSFetchResults+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/6.
//

import Foundation
import SwiftUI
import CoreData

extension FetchedResults: @retroactive Equatable where Result: Equatable {
    public static func == (lhs: FetchedResults, rhs: FetchedResults) -> Bool {
        Array(lhs) == Array(rhs)
    }
}
