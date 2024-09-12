import Foundation

// XML文件路径
let xmlPath = "../archives-new/appcast.xml"
let url = URL(fileURLWithPath: xmlPath)

// 读取XML数据
guard let xmlData = try? Data(contentsOf: url) else {
    print("Failed to load XML data.")
    exit(1)
}

// 创建XML解析器
var downloadUrl = ""
var maxVersion = 0
let parser = XMLParser(data: xmlData)
let xmlDelegate = XMLDelegate()

class XMLDelegate: NSObject, XMLParserDelegate {
    var currentElement = ""
    var url = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        // print(#function, elementName)
        if (attributeDict.keys.contains("sparkle:deltaFrom")) { return }
        currentElement = elementName
        if elementName == "enclosure" {
            url = attributeDict["url"] ?? ""
        } else if elementName == "item" {
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        if currentElement == "sparkle:version" {
            // print(#function, trimmedString, maxVersion, Int(trimmedString) ?? 0)
            let version = Int(trimmedString) ?? 0
            if version > maxVersion {
                // print("Get greater version: \(version), url: \(url)")
                maxVersion = version
                downloadUrl = url
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
          if downloadUrl.isEmpty {
            downloadUrl = url
          }
          url = "";
        }
    }
}

parser.delegate = xmlDelegate

// 开始解析
if parser.parse() {
    print(URL(string: downloadUrl)!.path(percentEncoded: true).components(separatedBy: "/").last!)
}
