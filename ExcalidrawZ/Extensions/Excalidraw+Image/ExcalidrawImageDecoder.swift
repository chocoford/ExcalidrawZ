//
//  ExcalidrawImageDecoder.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/11.
//

import Foundation
import Compression

class ExcalidrawImageDecoder {
    
    public init() {}

    struct EncodedData: Codable {
        var encoded: String
        var encoding: Encoding
        var compressed: Bool
        var version: String?
        
        enum Encoding: String, Codable {
            case bstring
        }
    }
    
    
    internal func byteStringToString(_ byteString: String) -> String {
        String(data: byteStringToData(byteString), encoding: .utf8) ?? ""
    }
    
    internal func byteStringToData(_ byteString: String) -> Data {
        var byteArray = [UInt8]()
        for utf16Unit in byteString.utf16 {
            byteArray.append(UInt8(utf16Unit & 0xFF))
        }
        return Data(byteArray)
    }
    
    // 解压缩函数
    internal func inflate(_ encodedString: String) throws -> String {
//        print("infalte - \(encodedString)")
        let data = byteStringToData(encodedString)
        
        let decompressedData = data.decompressed
        
        guard let decompressedString = String(data: decompressedData, encoding: .utf8) else {
            throw NSError(
                domain: "inflate",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert decompressed data to string"]
            )
        }
        
        return decompressedString
    }

    // 用于解压缩数据的函数
    internal func decompressData(data: Data) throws -> Data {
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var decompressedData = Data()
        
        let decompressionStream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer {
            compression_stream_destroy(decompressionStream)
            decompressionStream.deallocate()
        }
        
        guard compression_stream_init(decompressionStream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw NSError(domain: "inflate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize compression stream"])
        }
        
        // 设置源数据
        data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            decompressionStream.pointee.src_ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            decompressionStream.pointee.src_size = data.count
        }
        let buf = buffer
        // 使用 buffer 指针进行解压缩
        try buffer.withUnsafeMutableBytes { (bufferPointer: UnsafeMutableRawBufferPointer) in
            guard let dstPtr = bufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw NSError(domain: "inflate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get buffer pointer"])
            }
            
            decompressionStream.pointee.dst_ptr = dstPtr
            decompressionStream.pointee.dst_size = bufferSize
            
            while true {
                let status = compression_stream_process(decompressionStream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                
                switch status {
                    case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                        // 计算已解压缩的字节数
                        let bytesDecompressed = bufferSize - decompressionStream.pointee.dst_size
                        decompressedData.append(buf, count: bytesDecompressed)
                        
                        // 重置目标缓冲区的指针和大小
                        decompressionStream.pointee.dst_ptr = dstPtr
                        decompressionStream.pointee.dst_size = bufferSize
                        
                        if status == COMPRESSION_STATUS_END {
                            return
                        }
                    default:
                        // 解压缩失败
                        throw NSError(
                            domain: "inflate",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Decompression failed with status \(status)"]
                        )
                }
            }
        }
        
        return decompressedData
    }

    
    internal func decodeEncodedData(data: Data) throws -> String {
        // decode
        var decoded: String = ""
        let encodedData = try JSONDecoder().decode(EncodedData.self, from: data)
        switch encodedData.encoding {
            case .bstring:
                // 如果是压缩的，则不需要重复解码
                if encodedData.compressed {
                    decoded = encodedData.encoded
                } else {
                    decoded = byteStringToString(encodedData.encoded)
                }
        }
        
        if encodedData.compressed {
            decoded = try self.inflate(decoded)
        }
        
        return decoded
    }
}
