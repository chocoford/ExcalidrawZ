//
//  CloudStorageTrashWebDestination.swift
//  ExcalidrawZ
//

import Foundation

enum CloudStorageTrashWebDestination: Equatable {
    case website(URL)
    case oneDrive

    static func destination(
        for location: CloudStorageLocation,
        accountDisplayName: String?
    ) -> Self? {
        switch location.providerID {
            case .microsoftOneDrive:
                return .oneDrive
            case .googleDrive:
                return website("https://drive.google.com/drive/trash")
            case .dropbox:
                return website("https://www.dropbox.com/deleted_files")
            case .box:
                return website("https://app.box.com/trash")
            case .webDAV:
                guard let serverURL = URL(string: location.rootItemID.rawValue) else {
                    return nil
                }
                let service = WebDAVServiceIdentity.service(for: serverURL)
                    ?? WebDAVServiceIdentity.service(forAccountDisplayName: accountDisplayName)
                switch service {
                    case .pCloud:
                        return website("https://my.pcloud.com/#page=trash")
                    case .nextcloud:
                        guard var components = webComponents(for: serverURL),
                              let davPath = components.percentEncodedPath.range(of: "/remote.php/") else {
                            return nil
                        }
                        let basePath = components.percentEncodedPath[..<davPath.lowerBound]
                        components.percentEncodedPath = basePath + "/index.php/apps/files/trashbin"
                        return components.url.map(Self.website)
                    default:
                        // WebDAV has no standard recycle bin or browser route.
                        return nil
                }
            default:
                return nil
        }
    }

    /// Resolve the actual drive website so work/school accounts stay on their SharePoint site.
    static func oneDriveURL(for remoteURL: URL) -> URL? {
        guard var components = webComponents(for: remoteURL),
              let host = components.host?.lowercased() else {
            return nil
        }
        if host == "onedrive.live.com" {
            let accountID = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cid" })?.value
            components.scheme = "https"
            components.port = nil
            components.path = "/"
            components.queryItems = [
                URLQueryItem(name: "id", value: "root"),
                URLQueryItem(name: "qt", value: "recyclebin")
            ]
            if let accountID, accountID.count == 16, accountID.allSatisfy(\.isHexDigit) {
                components.queryItems?.append(URLQueryItem(name: "cid", value: accountID))
            }
            return components.url
        }

        let sharePointDomains = ["sharepoint.com", "sharepoint.cn", "sharepoint.us", "sharepoint-mil.us", "sharepoint.de"]
        guard sharePointDomains.contains(where: { host.hasSuffix("." + $0) }) else {
            return nil
        }

        var path = components.percentEncodedPath.split(separator: "/").map(String.init)
        // Graph may return a SharePoint sharing URL, e.g. /:f:/r/sites/Design/Documents/...
        if path.first?.hasPrefix(":") == true {
            guard path.count >= 2, path[1] == "r" else { return nil }
            path.removeFirst(2)
        }
        let managedPaths = ["personal", "sites", "teams"]
        let sitePath: String
        if let first = path.first, managedPaths.contains(first.lowercased()) {
            guard path.count >= 2 else { return nil }
            sitePath = "/" + path.prefix(2).joined(separator: "/")
        } else {
            sitePath = ""
        }
        components.scheme = "https"
        components.port = nil
        components.percentEncodedPath = sitePath + "/_layouts/15/RecycleBin.aspx"
        return components.url
    }

    private static func website(_ value: String) -> Self? {
        URL(string: value).map(Self.website)
    }

    private static func webComponents(for url: URL) -> URLComponents? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }
        // Browser navigation uses its own login, never credentials or signed URL parameters.
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components
    }
}
