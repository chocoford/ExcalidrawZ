//
//  WebDAVClient.swift
//  ExcalidrawZ
//

import Foundation
import Logging

struct WebDAVItemInspection: Sendable {
    let resource: WebDAVResource
    let response: WebDAVServiceProbeResponse
}

struct WebDAVEndpointResolution: Sendable {
    let serverURL: URL
    let inspection: WebDAVItemInspection
}

struct WebDAVClient: Sendable {
    private let logger = Logger(label: "WebDAVClient")
    private let credential: WebDAVCredential
    private let urlSession: URLSession

    init(
        credential: WebDAVCredential,
        urlSession: URLSession = .shared
    ) {
        self.credential = credential
        self.urlSession = urlSession
    }

    func item(at url: URL) async throws -> WebDAVResource {
        try await inspectItem(at: url).resource
    }

    func inspectItem(at url: URL) async throws -> WebDAVItemInspection {
        let result = try await properties(at: url, depth: 0)
        guard let item = result.resources.first else {
            throw CloudStorageError.itemNotFound(
                CloudStorageItemID(rawValue: url.absoluteString)
            )
        }
        return WebDAVItemInspection(resource: item, response: result.response)
    }

    func resolveEndpoint(from serverURL: URL) async throws -> WebDAVEndpointResolution {
        let directCandidates = WebDAVURL.endpointCandidates(
            for: serverURL,
            username: credential.username
        )
        var candidates = [directCandidates[0]]
        var endpointSources = [serverURL]

        if let declaredURL = await discoverNextcloudWebDAVRoot(from: serverURL) {
            endpointSources.insert(declaredURL, at: 0)
        }

        for wellKnownURL in WebDAVURL.wellKnownEndpointURLs(for: serverURL) {
            guard let discoveredURL = await discoverEndpoint(at: wellKnownURL) else {
                continue
            }
            endpointSources.append(discoveredURL)
        }

        var userIDs = [credential.username]
        for sourceURL in endpointSources {
            if let userID = await discoverNextcloudUserID(from: sourceURL),
               !userIDs.contains(userID) {
                userIDs.insert(userID, at: 0)
            }
        }

        for sourceURL in endpointSources {
            for userID in userIDs {
                candidates.append(contentsOf: WebDAVURL.endpointCandidates(
                    for: sourceURL,
                    username: userID
                ))
            }
        }
        candidates.append(contentsOf: directCandidates.dropFirst())

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.absoluteString).inserted }
        var lastError: Error?
        var preferredNextcloudError: Error?

        for candidate in candidates {
            do {
                let inspection = try await inspectItem(at: candidate)
                logger.debug(
                    "Resolved WebDAV endpoint url=\(candidate.absoluteString)"
                )
                return WebDAVEndpointResolution(
                    serverURL: candidate,
                    inspection: inspection
                )
            } catch let error as CloudStorageError {
                logger.debug(
                    "Rejected WebDAV endpoint url=\(candidate.absoluteString) error=\(error.localizedDescription)"
                )
                switch error {
                    case .authenticationRequired, .permissionDenied:
                        throw error
                    default:
                        lastError = error
                        if candidate.path.lowercased().contains("/remote.php/dav/files/") {
                            preferredNextcloudError = error
                        }
                }
            } catch {
                logger.debug(
                    "Rejected WebDAV endpoint url=\(candidate.absoluteString) error=\(error.localizedDescription)"
                )
                lastError = error
                if candidate.path.lowercased().contains("/remote.php/dav/files/") {
                    preferredNextcloudError = error
                }
            }
        }

        throw preferredNextcloudError ?? lastError ?? CloudStorageError.invalidProviderResponse(
            "Unable to discover a WebDAV endpoint for this server."
        )
    }

    func detectService(
        at serverURL: URL,
        webDAVResponse: WebDAVServiceProbeResponse
    ) async -> WebDAVService? {
        if let service = WebDAVServiceIdentity.service(for: serverURL) {
            return service
        }
        if let service = WebDAVServiceFingerprint.service(
            inWebDAVResponse: webDAVResponse
        ) {
            return service
        }

        return await withTaskGroup(of: WebDAVService?.self) { group in
            for probe in WebDAVServiceFingerprint.probes(for: serverURL) {
                group.addTask {
                    await self.probeService(with: probe)
                }
            }

            while let service = await group.next() {
                if let service {
                    group.cancelAll()
                    return service
                }
            }
            return nil
        }
    }

    func children(of folderURL: URL) async throws -> [WebDAVResource] {
        let folderURL = WebDAVURL.canonicalItemURL(folderURL, isCollection: true)
        return try await properties(at: folderURL, depth: 1).resources.filter {
            WebDAVURL.canonicalItemURL($0.url, isCollection: $0.isCollection) != folderURL
        }
    }

    func download(_ url: URL, to localURL: URL) async throws {
        let request = request(url: url, method: "GET")
        let (temporaryURL, response) = try await urlSession.download(for: request)
        try validate(response, operation: .download, itemURL: url)
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: temporaryURL, to: localURL)
    }

    func createFile(
        named name: String,
        in parentURL: URL,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> WebDAVResource {
        let destinationURL = try WebDAVURL.childURL(
            named: name,
            in: parentURL,
            isCollection: false
        )
        var request = request(url: destinationURL, method: "PUT")
        apply(condition, to: &request)
        let (_, response) = try await urlSession.upload(for: request, fromFile: localURL)
        try validate(response, operation: .createFile, itemURL: destinationURL)
        return try await item(at: destinationURL)
    }

    func updateFile(
        _ url: URL,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> WebDAVResource {
        var request = request(url: url, method: "PUT")
        apply(condition, to: &request)
        let (_, response) = try await urlSession.upload(for: request, fromFile: localURL)
        try validate(response, operation: .updateFile, itemURL: url)
        return try await item(at: url)
    }

    func createFolder(named name: String, in parentURL: URL) async throws -> WebDAVResource {
        let destinationURL = try WebDAVURL.childURL(
            named: name,
            in: parentURL,
            isCollection: true
        )
        let request = request(url: destinationURL, method: "MKCOL")
        let (_, response) = try await urlSession.data(for: request)
        try validate(response, operation: .createFolder, itemURL: destinationURL)
        return try await item(at: destinationURL)
    }

    func moveItem(
        at sourceURL: URL,
        to parentURL: URL?,
        newName: String?,
        isCollection: Bool
    ) async throws -> WebDAVResource {
        let destinationParentURL = parentURL
            ?? WebDAVURL.canonicalItemURL(
                sourceURL.deletingLastPathComponent(),
                isCollection: true
            )
        let destinationName = newName ?? sourceURL.lastPathComponent
        let destinationURL = try WebDAVURL.childURL(
            named: destinationName,
            in: destinationParentURL,
            isCollection: isCollection
        )
        if destinationURL == sourceURL {
            return try await item(at: sourceURL)
        }

        var request = request(url: sourceURL, method: "MOVE")
        request.setValue(destinationURL.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue("F", forHTTPHeaderField: "Overwrite")
        let (_, response) = try await urlSession.data(for: request)
        try validate(response, operation: .moveItem, itemURL: sourceURL)
        return try await item(at: destinationURL)
    }

    func delete(
        _ url: URL,
        condition: CloudStorageWriteCondition
    ) async throws {
        var request = request(url: url, method: "DELETE")
        apply(condition, to: &request)
        let (_, response) = try await urlSession.data(for: request)
        try validate(response, operation: .deleteItem, itemURL: url)
    }

    private func properties(
        at url: URL,
        depth: Int
    ) async throws -> (resources: [WebDAVResource], response: WebDAVServiceProbeResponse) {
        var request = request(url: url, method: "PROPFIND")
        request.setValue(String(depth), forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.propertyRequestBody
        let (data, response) = try await urlSession.data(for: request)
        logFailedWebDAVResponse(
            data: data,
            response: response,
            requestURL: url,
            acceptedStatusCodes: [207]
        )
        try validate(
            response,
            operation: .browse,
            itemURL: url,
            acceptedStatusCodes: [207],
            body: data
        )
        let resources = try WebDAVMultiStatusParser(responseURL: url).parse(data)
        if resources.isEmpty {
            logger.debug(
                "Parsed empty WebDAV multi-status response url=\(url.absoluteString) body=\(Self.responseBodySummary(data))"
            )
        }
        return (
            resources,
            responseEvidence(response, body: data)
        )
    }

    private func probeService(with probe: WebDAVServiceProbe) async -> WebDAVService? {
        guard !Task.isCancelled else { return nil }
        var request = URLRequest(url: probe.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("ExcalidrawZ WebDAV", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await urlSession.data(for: request) else {
            return nil
        }
        return WebDAVServiceFingerprint.service(
            in: responseEvidence(response, body: data),
            for: probe
        )
    }

    private func discoverEndpoint(at wellKnownURL: URL) async -> URL? {
        var request = request(url: wellKnownURL, method: "GET")
        request.timeoutInterval = 15

        guard let (_, response) = try? await urlSession.data(for: request),
              let responseURL = response.url else {
            return nil
        }

        if responseURL != wellKnownURL,
           WebDAVURL.isUsableDiscoveredEndpointURL(responseURL) {
            let endpointURL = WebDAVURL.canonicalItemURL(responseURL, isCollection: true)
            logger.debug(
                "Discovered WebDAV endpoint through well-known url=\(endpointURL.absoluteString)"
            )
            return endpointURL
        }
        if let response = response as? HTTPURLResponse,
           let location = response.value(forHTTPHeaderField: "Location"),
           let redirectURL = URL(string: location, relativeTo: wellKnownURL)?.absoluteURL,
           WebDAVURL.isUsableDiscoveredEndpointURL(redirectURL) {
            let endpointURL = WebDAVURL.canonicalItemURL(redirectURL, isCollection: true)
            logger.debug(
                "Discovered WebDAV endpoint through redirect url=\(endpointURL.absoluteString)"
            )
            return endpointURL
        }
        if responseURL != wellKnownURL {
            logger.debug(
                "Ignored invalid WebDAV well-known result url=\(responseURL.absoluteString)"
            )
        }
        return nil
    }

    private func discoverNextcloudUserID(from serverURL: URL) async -> String? {
        for url in WebDAVURL.nextcloudCurrentUserURLs(for: serverURL) {
            var request = request(url: url, method: "GET")
            request.timeoutInterval = 15
            request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await urlSession.data(for: request),
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let userID = Self.nextcloudUserID(in: data) else {
                continue
            }
            logger.debug(
                "Resolved Nextcloud user ID login=\(credential.username) userID=\(userID)"
            )
            return userID
        }
        return nil
    }

    private func discoverNextcloudWebDAVRoot(from serverURL: URL) async -> URL? {
        for url in WebDAVURL.nextcloudCapabilitiesURLs(for: serverURL) {
            var request = request(url: url, method: "GET")
            request.timeoutInterval = 15
            request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await urlSession.data(for: request),
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let declaredRoot = Self.nextcloudWebDAVRoot(in: data),
                  let resolvedURL = WebDAVURL.resolvedServerDeclaredEndpoint(
                    declaredRoot,
                    relativeTo: serverURL
                  ) else {
                continue
            }
            logger.debug(
                "Resolved server-declared Nextcloud WebDAV root value=\(declaredRoot) url=\(resolvedURL.absoluteString)"
            )
            return resolvedURL
        }
        return nil
    }

    static func nextcloudUserID(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let ocs = root["ocs"] as? [String: Any],
              let responseData = ocs["data"] as? [String: Any],
              let userID = responseData["id"] as? String else {
            return nil
        }
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedUserID.isEmpty ? nil : normalizedUserID
    }

    static func nextcloudWebDAVRoot(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let ocs = root["ocs"] as? [String: Any],
              let responseData = ocs["data"] as? [String: Any],
              let capabilities = responseData["capabilities"] as? [String: Any],
              let core = capabilities["core"] as? [String: Any],
              let webDAVRoot = core["webdav-root"] as? String else {
            return nil
        }
        let normalizedRoot = webDAVRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedRoot.isEmpty ? nil : normalizedRoot
    }

    private func logFailedWebDAVResponse(
        data: Data,
        response: URLResponse,
        requestURL: URL,
        acceptedStatusCodes: Set<Int>
    ) {
        guard let response = response as? HTTPURLResponse,
              !acceptedStatusCodes.contains(response.statusCode) else { return }

        let body = Self.responseBodySummary(data)
        let finalURL = response.url?.absoluteString ?? requestURL.absoluteString
        let server = response.value(forHTTPHeaderField: "Server") ?? "none"
        let dav = response.value(forHTTPHeaderField: "DAV") ?? "none"
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "none"
        logger.debug(
            "WebDAV request rejected status=\(response.statusCode) requestURL=\(requestURL.absoluteString) finalURL=\(finalURL) server=\(server) dav=\(dav) contentType=\(contentType) body=\(body)"
        )
    }

    private static func responseBodySummary(_ data: Data) -> String {
        String(decoding: data.prefix(512), as: UTF8.self)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func responseEvidence(
        _ response: URLResponse,
        body: Data
    ) -> WebDAVServiceProbeResponse {
        guard let response = response as? HTTPURLResponse else {
            return WebDAVServiceProbeResponse(statusCode: 0, headers: [:], body: body)
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key).lowercased()] = String(describing: entry.value)
        }
        return WebDAVServiceProbeResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: body
        )
    }

    private func request(
        url: URL,
        method: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("ExcalidrawZ WebDAV", forHTTPHeaderField: "User-Agent")
        if WebDAVURL.hasSameOrigin(url, as: credential.serverURL) {
            let authorization = Data("\(credential.username):\(credential.password)".utf8)
                .base64EncodedString()
            request.setValue("Basic \(authorization)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func apply(
        _ condition: CloudStorageWriteCondition,
        to request: inout URLRequest
    ) {
        switch condition {
            case .unconditional:
                break
            case .ifAbsent:
                request.setValue("*", forHTTPHeaderField: "If-None-Match")
            case .ifUnmodified(let revision):
                request.setValue(revision, forHTTPHeaderField: "If-Match")
        }
    }

    private func validate(
        _ response: URLResponse,
        operation: CloudStorageOperation,
        itemURL: URL,
        acceptedStatusCodes: Set<Int> = Set(200..<300),
        body: Data? = nil
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse(
                "WebDAV did not return an HTTP response."
            )
        }
        guard !acceptedStatusCodes.contains(response.statusCode) else { return }

        switch response.statusCode {
            case 401:
                throw CloudStorageError.authenticationRequired
            case 403:
                throw CloudStorageError.permissionDenied(operation)
            case 404:
                throw CloudStorageError.itemNotFound(
                    CloudStorageItemID(rawValue: itemURL.absoluteString)
                )
            case 405 where operation == .createFile || operation == .createFolder:
                throw CloudStorageError.itemNameAlreadyExists(itemURL.lastPathComponent)
            case 409 where operation == .createFile || operation == .createFolder:
                throw CloudStorageError.itemNameAlreadyExists(itemURL.lastPathComponent)
            case 409, 412, 423:
                throw CloudStorageError.conflict
            case 429:
                throw CloudStorageError.rateLimited(
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                )
            case 503 where Self.isTemporaryRateLimitResponse(body):
                throw CloudStorageError.rateLimited(
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init) ?? 300
                )
            default:
                throw CloudStorageError.transport(
                    "WebDAV returned HTTP \(response.statusCode) for \(operation.rawValue) at \(itemURL.path)."
                )
        }
    }

    private static func isTemporaryRateLimitResponse(_ body: Data?) -> Bool {
        guard let body else { return false }
        let responseText = String(decoding: body, as: UTF8.self).lowercased()
        return responseText.contains("blockedtemporarily")
            || responseText.contains("too many requests")
    }

    private static let propertyRequestBody = Data(
        """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname />
            <d:resourcetype />
            <d:getcontenttype />
            <d:getcontentlength />
            <d:creationdate />
            <d:getlastmodified />
            <d:getetag />
          </d:prop>
        </d:propfind>
        """.utf8
    )
}
