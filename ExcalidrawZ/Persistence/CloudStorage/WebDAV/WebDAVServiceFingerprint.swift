//
//  WebDAVServiceFingerprint.swift
//  ExcalidrawZ
//

import Foundation

struct WebDAVServiceProbe: Sendable {
    enum Kind: Sendable {
        case nextcloudStatus
        case openListSettings
        case seafilePing
    }

    let kind: Kind
    let url: URL
}

struct WebDAVServiceProbeResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

enum WebDAVServiceFingerprint {
    static func service(
        inWebDAVResponse response: WebDAVServiceProbeResponse
    ) -> WebDAVService? {
        let headerSignal = response.headers
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")
            .lowercased()

        if headerSignal.contains("nextcloud") { return .nextcloud }
        if headerSignal.contains("owncloud") { return .ownCloud }
        if headerSignal.contains("openlist") { return .openList }
        if headerSignal.contains("seafile") || headerSignal.contains("seafdav") {
            return .seafile
        }
        return nil
    }

    static func probes(for serverURL: URL) -> [WebDAVServiceProbe] {
        applicationBaseURLs(for: serverURL).flatMap { baseURL in
            [
                WebDAVServiceProbe(
                    kind: .nextcloudStatus,
                    url: baseURL.appending(path: "status.php", directoryHint: .notDirectory)
                ),
                WebDAVServiceProbe(
                    kind: .openListSettings,
                    url: baseURL.appending(
                        path: "api/public/settings",
                        directoryHint: .notDirectory
                    )
                ),
                WebDAVServiceProbe(
                    kind: .seafilePing,
                    url: baseURL.appending(path: "api2/ping/", directoryHint: .notDirectory)
                ),
            ]
        }
    }

    static func service(
        in response: WebDAVServiceProbeResponse,
        for probe: WebDAVServiceProbe
    ) -> WebDAVService? {
        guard (200..<300).contains(response.statusCode) else { return nil }

        switch probe.kind {
            case .nextcloudStatus:
                return nextcloudFamilyService(in: response.body)
            case .openListSettings:
                return isOpenListSettings(response.body) ? .openList : nil
            case .seafilePing:
                return isSeafilePing(response.body) ? .seafile : nil
        }
    }

    private static func applicationBaseURLs(for serverURL: URL) -> [URL] {
        guard var components = URLComponents(
            url: serverURL,
            resolvingAgainstBaseURL: false
        ) else { return [] }

        components.query = nil
        components.fragment = nil
        let serverPath = components.percentEncodedPath
        var paths = ["/"]
        let lowercasedPath = serverPath.lowercased() as NSString
        let originalPath = serverPath as NSString

        for marker in ["/remote.php/", "/seafdav/", "/dav/"] {
            let range = lowercasedPath.range(of: marker)
            guard range.location != NSNotFound else { continue }
            let prefix = originalPath.substring(to: range.location)
            paths.insert(prefix.isEmpty ? "/" : prefix + "/", at: 0)
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            components.percentEncodedPath = path
            guard let url = components.url, seen.insert(url.absoluteString).inserted else {
                return nil
            }
            return url
        }
    }

    private static func nextcloudFamilyService(in data: Data) -> WebDAVService? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let productName = dictionary["productname"] as? String else {
            return nil
        }

        switch productName.lowercased() {
            case let name where name.contains("nextcloud"): return .nextcloud
            case let name where name.contains("owncloud"): return .ownCloud
            default: return nil
        }
    }

    private static func isOpenListSettings(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let settings = dictionary["data"] as? [String: Any] else {
            return false
        }

        let identifyingValues = ["site_title", "logo", "favicon", "audio_cover"]
            .compactMap { settings[$0] as? String }
            .joined(separator: "\n")
            .lowercased()
        if identifyingValues.contains("openlist") { return true }

        guard let version = settings["version"] as? String else { return false }
        let majorVersion = version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .first
            .flatMap { Int($0) }
        return majorVersion.map { $0 >= 4 } ?? false
    }

    private static func isSeafilePing(_ data: Data) -> Bool {
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
            return false
        }
        return value.caseInsensitiveCompare("pong") == .orderedSame
    }
}
