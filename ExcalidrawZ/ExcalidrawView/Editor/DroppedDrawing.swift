import Foundation

struct DroppedDrawing: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let file: ExcalidrawFile
    let targetFileID: String

    init(fileName: String, fileSize: Int, dataString: String, targetFileID: String) throws {
        let data = Data(dataString.utf8)
        // File.text() removes a leading UTF-8 byte-order mark.
        guard fileSize == data.count || fileSize == data.count + 3,
              var file = try? JSONDecoder().decode(DrawingContents.self, from: data).file,
              file.type == "excalidraw" else {
            throw ImportError.invalidDrawing
        }

        let name = (fileName as NSString).lastPathComponent
        let baseName = (name as NSString).deletingPathExtension
        file.content = data
        file.name = baseName.isEmpty ? nil : baseName
        self.fileName = name
        self.file = file
        self.targetFileID = targetFileID
    }

    private struct DrawingContents: Decodable {
        private enum CodingKeys: String, CodingKey {
            case elements
        }

        let file: ExcalidrawFile

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard try !container.decodeNil(forKey: .elements) else {
                throw ImportError.invalidDrawing
            }
            file = try ExcalidrawFile(from: decoder)
        }
    }

    enum ImportError: LocalizedError {
        case invalidDrawing
        case replacementUnavailable

        var errorDescription: String? {
            switch self {
                case .invalidDrawing:
                    String(localizable: .drawingDropInvalidFile)
                case .replacementUnavailable:
                    String(localizable: .drawingDropReplacementUnavailable)
            }
        }
    }
}
