//
//  ExcalidrawPNGDecoder.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/10.
//

import Foundation
import Compression

import Zlib

class ExcalidrawPNGDecoder: ExcalidrawImageDecoder {
    struct PNGChunk {
        let length: UInt32
        let type: String
        let data: Data
        let crc: UInt32
    }
    
    struct TextChunk {
        var keyword: String
        var text: String
    }
    

    func decode(from imageData: Data) -> ExcalidrawFile? {
        guard !self.isValidJSON(imageData) else { return nil }
        
        guard let textChunk = findTextChunk(from: imageData) else {
            return nil
        }
        let chunk = TextChunk(keyword: textChunk.0, text: textChunk.1)
        guard chunk.keyword == "application/vnd.excalidraw+json" else {
            return nil
        }
        
        /// packages/excalidraw/data/image.ts - 47
        guard let textData = chunk.text.data(using: .utf8) else {
            return nil
        }
        do {
            guard let encodedData = try JSONSerialization.jsonObject(with: textData) as? [String : Any] else {
                return nil
            }
            
            if encodedData.keys.contains("encoded") {
                let decoded = try self.decodeEncodedData(data: textData)
                
                if let data = decoded.data(using: .utf8) {
//                    print(try? JSONSerialization.jsonObject(with: data))
                    return try ExcalidrawFile(data: data)
                }
                
            } else if let type = encodedData["type"] as? String, type == "excalidraw" {
                if let data = chunk.text.data(using: .utf8) {
                    return try ExcalidrawFile(data: data)
                }
            }
        } catch {
            print(error)
            return nil
        }
        
        if let data = chunk.text.data(using: .utf8) {
            return try? ExcalidrawFile(data: data)
        } else {
            return nil
        }
    }
}

extension ExcalidrawPNGDecoder {
    private func parsePNGChunks(from data: Data) -> [PNGChunk] {
        var chunks: [PNGChunk] = []
        var offset = 8 // 跳过 PNG 文件的前 8 个字节（文件头部）

        while offset < data.count {
            // 读取 chunk 长度（4 字节）
            let length = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            }
            offset += 4
            
            // 读取 chunk 类型（4 字节）
            let typeData = data.subdata(in: offset..<(offset + 4))
            guard let type = String(data: typeData, encoding: .ascii) else { break }
            offset += 4
            
            // 读取 chunk 数据
            let chunkData = data.subdata(in: offset..<(offset + Int(length)))
            offset += Int(length)
            
            // 读取 CRC 校验码（4 字节）
            let crc = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            }
            offset += 4
            
            // 添加解析后的 chunk
            chunks.append(PNGChunk(length: length, type: type, data: chunkData, crc: crc))
        }
        
        return chunks
    }

    private func findTextChunk(from imageData: Data) -> (keyword: String, text: String)? {
        let chunks = parsePNGChunks(from: imageData)
        if let metadataChunk = chunks.first(where: {$0.type == "tEXt"}) {
            return decodeTextChunk(from: metadataChunk.data)
        }
        return nil
    }
    
    /// https://github.com/hughsk/png-chunk-text/blob/master/decode.js
    private func decodeTextChunk(from data: Data) -> (keyword: String, text: String)? {
        var naming = true
        var keyword = ""
        var text = ""
        
        for byte in data {
            if naming {
                if byte != 0 {
                    keyword.append(Character(UnicodeScalar(byte)))
                } else {
                    naming = false
                }
            } else {
                if byte != 0 {
                    text.append(Character(UnicodeScalar(byte)))
                } else {
                    print("Error: Invalid NULL character found. 0x00 character is not permitted in tEXt content")
                    return nil
                }
            }
        }
        
        return (keyword, text)
    }
    
}
