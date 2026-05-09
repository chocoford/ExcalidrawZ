//
//  ExcalidrawNanoID.swift
//  ExcalidrawZ
//
//  Created by Codex
//

import Foundation

enum ExcalidrawNanoID {
    private static let alphabet = Array("ModuleSymbhasOwnPr-0123456789ABCDEFGHIJKLNQRTUVWXYZ_cfgijkpqtvxz")

    static func make(size: Int = 21) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<size).map { _ in
            alphabet.randomElement(using: &generator) ?? "0"
        })
    }
}
