//
//  ExcalidrawSVGDecoder.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/11.
//

import Foundation

class ExcalidrawSVGDecoder: ExcalidrawImageDecoder {
    
    func decode(from data: Data) -> ExcalidrawFile? {
        guard let svg = String(data: data, encoding: .utf8) else {
            return nil
        }
        guard svg.contains("payload-type:application/vnd.excalidraw+json") else {
            return nil
        }
        
        let payloadPattern = "<!-- payload-start -->\\s*(.+?)\\s*<!-- payload-end -->"
        
        guard let match = svg.range(of: payloadPattern, options: .regularExpression) else {
            return nil
        }
        
        let payload = String(svg[match]).replacingOccurrences(of: "<!-- payload-start -->", with: "")
            .replacingOccurrences(of: "<!-- payload-end -->", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
                
        let versionPattern = "<!-- payload-version:(\\d+) -->"
        let versionMatch = svg.range(of: versionPattern, options: .regularExpression)
        let version = versionMatch.map { String(svg[$0]).components(separatedBy: ":")[1].replacingOccurrences(of: " -->", with: "") } ?? "1"
        let isByteString = version != "1"
        do {
            let jsonString = isByteString ? base64ToAscii(base64String: payload) ?? "" : byteStringToString(base64ToAscii(base64String: payload) ?? "")
            guard let jsonData = jsonString.data(using: .utf8),
                  let encodedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }
            
            if let _ = encodedData["encoded"] {
                let decoded = try self.decodeEncodedData(data: jsonData)
                if let data = decoded.data(using: .utf8) {
                    return try ExcalidrawFile(data: data)
                }
                return nil
            } else if let type = encodedData["type"] as? String, type == "application/vnd.excalidraw+json" {
                return try ExcalidrawFile(data: jsonData)
            } else {
                return nil
            }
        } catch {
            print(error)
            return nil
        }
    }
}

extension ExcalidrawSVGDecoder {
    private func base64ToAscii(base64String: String) -> String? {
        guard let data = Data(base64Encoded: base64String) else {
            return nil
        }

        // 将每个字节解码为 ASCII 字符
        let asciiString = data.reduce("") { (result, byte) in
            result + String(UnicodeScalar(byte))
        }

        return asciiString
    }

}
