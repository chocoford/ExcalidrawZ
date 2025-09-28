//
//  UUID+Transferable.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 7/30/25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension UUID: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { $0.uuidString }
    }
}
