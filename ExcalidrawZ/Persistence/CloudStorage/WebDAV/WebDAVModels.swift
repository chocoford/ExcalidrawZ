//
//  WebDAVModels.swift
//  ExcalidrawZ
//

import Foundation

enum WebDAVURL {
    static func normalizedServerURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else {
            throw CloudStorageError.invalidProviderResponse(
                "Enter a valid WebDAV server URL."
            )
        }
        guard scheme == "https" || isLocalHTTP(components) else {
            throw CloudStorageError.invalidProviderResponse(
                "WebDAV connections must use HTTPS. HTTP is allowed only for localhost."
            )
        }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        var path = components.percentEncodedPath
        if path.isEmpty { path = "/" }
        if !path.hasSuffix("/") { path += "/" }
        components.percentEncodedPath = path
        guard let normalizedURL = components.url else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to normalize the WebDAV server URL."
            )
        }
        return normalizedURL
    }

    static func itemURL(for id: CloudStorageItemID) throws -> URL {
        guard let url = URL(string: id.rawValue), url.scheme != nil else {
            throw CloudStorageError.itemNotFound(id)
        }
        return url
    }

    static func hasSameOrigin(_ lhs: URL, as rhs: URL) -> Bool {
        guard let lhsComponents = URLComponents(
            url: lhs,
            resolvingAgainstBaseURL: false
        ), let rhsComponents = URLComponents(
            url: rhs,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }

        let lhsScheme = lhsComponents.scheme?.lowercased()
        let rhsScheme = rhsComponents.scheme?.lowercased()
        return lhsScheme == rhsScheme
            && lhsComponents.host?.lowercased() == rhsComponents.host?.lowercased()
            && effectivePort(lhsComponents, scheme: lhsScheme)
                == effectivePort(rhsComponents, scheme: rhsScheme)
    }

    static func canonicalItemURL(
        _ url: URL,
        isCollection: Bool
    ) -> URL {
        guard var components = URLComponents(
            url: url.absoluteURL,
            resolvingAgainstBaseURL: false
        ) else { return url.absoluteURL }
        components.query = nil
        components.fragment = nil
        var path = components.percentEncodedPath
        if path.isEmpty { path = "/" }
        if isCollection, !path.hasSuffix("/") { path += "/" }
        if !isCollection, path.count > 1, path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        return components.url ?? url.absoluteURL
    }

    static func childURL(named name: String, in parentURL: URL, isCollection: Bool) throws -> URL {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/") else {
            throw CloudStorageError.invalidProviderResponse(
                "WebDAV item names cannot contain a slash."
            )
        }
        return canonicalItemURL(
            parentURL.appending(path: name, directoryHint: isCollection ? .isDirectory : .notDirectory),
            isCollection: isCollection
        )
    }

    /// Candidate DAV roots for services such as Nextcloud that commonly ask
    /// users for the site URL instead of exposing the DAV endpoint up front.
    static func endpointCandidates(
        for serverURL: URL,
        username: String
    ) -> [URL] {
        let normalizedURL = canonicalItemURL(serverURL, isCollection: true)
        guard let applicationBaseURL = applicationBaseURL(for: normalizedURL) else {
            return [normalizedURL]
        }

        let nextcloudFilesBaseURL = applicationBaseURL
            .appending(path: "remote.php/dav/files", directoryHint: .isDirectory)
        let nextcloudFilesURL = appendingEncodedPathSegment(
            username,
            to: nextcloudFilesBaseURL
        )
        let legacyOwnCloudURL = applicationBaseURL
            .appending(path: "remote.php/webdav", directoryHint: .isDirectory)

        let normalizedPath = normalizedURL.path.lowercased()
        let orderedCandidates: [URL]
        if normalizedPath.contains("/remote.php/dav"),
           !normalizedPath.contains("/remote.php/dav/files/") {
            orderedCandidates = [nextcloudFilesURL, normalizedURL, legacyOwnCloudURL]
        } else {
            orderedCandidates = [normalizedURL, nextcloudFilesURL, legacyOwnCloudURL]
        }

        var seen = Set<String>()
        return orderedCandidates
            .map { canonicalItemURL($0, isCollection: true) }
            .filter { seen.insert($0.absoluteString).inserted }
    }

    static func wellKnownEndpointURLs(for serverURL: URL) -> [URL] {
        guard var originComponents = URLComponents(
            url: serverURL,
            resolvingAgainstBaseURL: false
        ) else { return [] }

        originComponents.path = "/.well-known/webdav"
        originComponents.query = nil
        originComponents.fragment = nil

        var candidates = [originComponents.url].compactMap { $0 }
        if let applicationBaseURL = applicationBaseURL(for: serverURL) {
            candidates.append(
                applicationBaseURL.appending(
                    path: ".well-known/webdav",
                    directoryHint: .notDirectory
                )
            )
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.absoluteString).inserted }
    }

    static func nextcloudCurrentUserURLs(for serverURL: URL) -> [URL] {
        nextcloudOCSURLs(
            path: "ocs/v1.php/cloud/user",
            for: serverURL
        )
    }

    static func nextcloudCapabilitiesURLs(for serverURL: URL) -> [URL] {
        nextcloudOCSURLs(
            path: "ocs/v1.php/cloud/capabilities",
            for: serverURL
        )
    }

    static func resolvedServerDeclaredEndpoint(
        _ endpoint: String,
        relativeTo serverURL: URL
    ) -> URL? {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return nil }

        if let absoluteURL = URL(string: endpoint), absoluteURL.scheme != nil {
            return canonicalItemURL(absoluteURL, isCollection: true)
        }

        guard let applicationBaseURL = applicationBaseURL(for: serverURL),
              var originComponents = URLComponents(
                url: serverURL,
                resolvingAgainstBaseURL: false
              ) else { return nil }
        originComponents.path = "/"
        originComponents.query = nil
        originComponents.fragment = nil

        let baseURL = endpoint.hasPrefix("/")
            ? originComponents.url
            : applicationBaseURL
        guard let baseURL,
              let resolvedURL = URL(string: endpoint, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return canonicalItemURL(resolvedURL, isCollection: true)
    }

    private static func nextcloudOCSURLs(
        path: String,
        for serverURL: URL
    ) -> [URL] {
        guard var originComponents = URLComponents(
            url: serverURL,
            resolvingAgainstBaseURL: false
        ) else { return [] }

        originComponents.path = "/"
        originComponents.query = nil
        originComponents.fragment = nil

        var baseURLs = [applicationBaseURL(for: serverURL), originComponents.url]
            .compactMap { $0 }
        var seen = Set<String>()
        baseURLs = baseURLs.filter { seen.insert($0.absoluteString).inserted }

        return baseURLs.compactMap { baseURL in
            guard var components = URLComponents(
                url: baseURL.appending(
                    path: path,
                    directoryHint: .notDirectory
                ),
                resolvingAgainstBaseURL: false
            ) else { return nil }
            components.queryItems = [URLQueryItem(name: "format", value: "json")]
            return components.url
        }
    }

    static func isUsableDiscoveredEndpointURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return !path.contains(".well-known")
            && !path.contains("/login")
    }

    private static func applicationBaseURL(for serverURL: URL) -> URL? {
        guard var components = URLComponents(
            url: serverURL,
            resolvingAgainstBaseURL: false
        ) else { return nil }

        let path = components.percentEncodedPath
        let lowercasedPath = path.lowercased() as NSString
        let originalPath = path as NSString
        for marker in ["/remote.php/", "/remote.php"] {
            let range = lowercasedPath.range(of: marker)
            guard range.location != NSNotFound else { continue }
            let prefix = originalPath.substring(to: range.location)
            components.percentEncodedPath = prefix.isEmpty ? "/" : prefix + "/"
            return components.url
        }

        components.percentEncodedPath = path.isEmpty
            ? "/"
            : (path.hasSuffix("/") ? path : path + "/")
        return components.url
    }

    private static func appendingEncodedPathSegment(
        _ segment: String,
        to parentURL: URL
    ) -> URL {
        guard var components = URLComponents(
            url: parentURL,
            resolvingAgainstBaseURL: false
        ), let encodedSegment = segment.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
            )
        ) else {
            return parentURL.appending(path: segment, directoryHint: .isDirectory)
        }

        var path = components.percentEncodedPath
        if !path.hasSuffix("/") { path += "/" }
        components.percentEncodedPath = path + encodedSegment + "/"
        return components.url
            ?? parentURL.appending(path: segment, directoryHint: .isDirectory)
    }
    
    private static func isLocalHTTP(_ components: URLComponents) -> Bool {
        guard components.scheme?.lowercased() == "http" else { return false }
        switch components.host?.lowercased() {
            case "localhost", "127.0.0.1", "::1": return true
            default: return false
        }
    }

    private static func effectivePort(
        _ components: URLComponents,
        scheme: String?
    ) -> Int? {
        if let port = components.port { return port }
        switch scheme {
            case "https": return 443
            case "http": return 80
            default: return nil
        }
    }
}

struct WebDAVResource: Sendable {
    let url: URL
    let displayName: String?
    let isCollection: Bool
    let contentType: String?
    let contentLength: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let etag: String?

    func cloudStorageItem(rootURL: URL) -> CloudStorageItem {
        let canonicalURL = WebDAVURL.canonicalItemURL(url, isCollection: isCollection)
        let canonicalRootURL = WebDAVURL.canonicalItemURL(rootURL, isCollection: true)
        let isRoot = canonicalURL == canonicalRootURL
        let parentURL = isRoot ? nil : WebDAVURL.canonicalItemURL(
            canonicalURL.deletingLastPathComponent(),
            isCollection: true
        )
        let fallbackName = canonicalURL.lastPathComponent.removingPercentEncoding
            ?? canonicalURL.lastPathComponent
        return CloudStorageItem(
            id: CloudStorageItemID(rawValue: canonicalURL.absoluteString),
            parentID: parentURL.map { CloudStorageItemID(rawValue: $0.absoluteString) },
            name: displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? fallbackName.nilIfEmpty
                ?? "WebDAV",
            kind: isCollection ? .folder : .file,
            contentType: contentType,
            size: contentLength,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            remoteURL: canonicalURL,
            revision: contentRevision,
            capabilities: isCollection ? .writableFolder : .writableFile
        )
    }

    /// ETag is optional in WebDAV. A stable metadata fallback prevents
    /// providers without ETags from redownloading unchanged files forever.
    private var contentRevision: String? {
        if let etag = etag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !etag.isEmpty {
            return etag
        }
        guard modifiedAt != nil || contentLength != nil else { return nil }
        return "webdav:\(modifiedAt?.timeIntervalSince1970 ?? -1):\(contentLength ?? -1)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

final class WebDAVMultiStatusParser: NSObject, XMLParserDelegate {
    private struct Properties {
        var displayName: String?
        var isCollection = false
        var contentType: String?
        var contentLength: String?
        var creationDate: String?
        var lastModified: String?
        var etag: String?
    }

    private struct Propstat {
        var properties = Properties()
        var status: String?

        var isSuccessful: Bool {
            guard let status else { return true }
            return status
                .split(separator: " ")
                .compactMap { Int($0) }
                .contains { (200..<300).contains($0) }
        }
    }

    private struct Response {
        var href: String?
        var propstats: [Propstat] = []
    }

    private let responseURL: URL
    private var currentResponse: Response?
    private var currentPropstat: Propstat?
    private var currentText = ""
    private var resources: [WebDAVResource] = []

    init(responseURL: URL) {
        self.responseURL = responseURL
    }

    func parse(_ data: Data) throws -> [WebDAVResource] {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        guard parser.parse() else {
            throw CloudStorageError.invalidProviderResponse(
                parser.parserError?.localizedDescription ?? "Unable to parse WebDAV response."
            )
        }
        return resources
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if name == "response" { currentResponse = Response() }
        if name == "propstat" { currentPropstat = Propstat() }
        if name == "collection" { currentPropstat?.properties.isCollection = true }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
            case "href": currentResponse?.href = value
            case "displayname": currentPropstat?.properties.displayName = value
            case "getcontenttype": currentPropstat?.properties.contentType = value
            case "getcontentlength": currentPropstat?.properties.contentLength = value
            case "creationdate": currentPropstat?.properties.creationDate = value
            case "getlastmodified": currentPropstat?.properties.lastModified = value
            case "getetag": currentPropstat?.properties.etag = value
            case "status": currentPropstat?.status = value
            case "propstat":
                if let currentPropstat {
                    currentResponse?.propstats.append(currentPropstat)
                }
                currentPropstat = nil
            case "response":
                if let response = currentResponse,
                   let resource = resource(from: response) {
                    resources.append(resource)
                }
                currentResponse = nil
            default: break
        }
        currentText = ""
    }

    private func resource(from response: Response) -> WebDAVResource? {
        guard let href = response.href,
              let resolvedURL = URL(string: href, relativeTo: responseURL)?.absoluteURL,
              WebDAVURL.hasSameOrigin(resolvedURL, as: responseURL),
              !response.propstats.isEmpty else {
            return nil
        }
        let successfulProperties = response.propstats
            .filter(\.isSuccessful)
            .map(\.properties)
        guard !successfulProperties.isEmpty else { return nil }

        let properties = successfulProperties.reduce(into: Properties()) { result, properties in
            result.displayName = result.displayName ?? properties.displayName?.nilIfEmpty
            result.isCollection = result.isCollection || properties.isCollection
            result.contentType = result.contentType ?? properties.contentType?.nilIfEmpty
            result.contentLength = result.contentLength ?? properties.contentLength?.nilIfEmpty
            result.creationDate = result.creationDate ?? properties.creationDate?.nilIfEmpty
            result.lastModified = result.lastModified ?? properties.lastModified?.nilIfEmpty
            result.etag = result.etag ?? properties.etag?.nilIfEmpty
        }
        return WebDAVResource(
            url: resolvedURL,
            displayName: properties.displayName,
            isCollection: properties.isCollection,
            contentType: properties.contentType,
            contentLength: properties.contentLength.flatMap(Int64.init),
            createdAt: Self.iso8601Date(properties.creationDate),
            modifiedAt: Self.httpDate(properties.lastModified),
            etag: properties.etag
        )
    }

    private static func iso8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value)
    }
}
