//
//  CollabRoomIDCoder.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import Foundation

class CollabRoomIDCoder {
    static let shared = CollabRoomIDCoder()
    
    private let key: UInt8 = 0xAA
    
    private func xorEncode(_ input: String, key: UInt8) -> String {
        let bytes = [UInt8](input.utf8)
        let encodedBytes = bytes.map { $0 ^ key }
        // 将每个字节转换为两位十六进制字符串并拼接
        return encodedBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    private func xorDecode(_ hex: String, key: UInt8) -> String? {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            // 确保有两个字符可供转换
            guard nextIndex <= hex.endIndex,
                  let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            // 还原原始字节
            bytes.append(byte ^ key)
            index = nextIndex
        }
        return String(bytes: bytes, encoding: .utf8)
    }
    
    public func encode(roomID: String) -> String {
        xorEncode(roomID, key: key)
    }
    public func decode(encodedString: String) -> String? {
        xorDecode(encodedString, key: key)
    }
}

