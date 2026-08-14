//
//  WebDAVServiceIdentity.swift
//  ExcalidrawZ
//

import Foundation

enum WebDAVService: String, CaseIterable, Codable, Sendable {
    case nutstore
    case koofr
    case pCloud
    case yandexDisk
    case infiniCloud
    case nextcloud
    case synology
    case ownCloud
    case qnap
    case openList
    case seafile

    var displayName: String {
        switch self {
            case .nutstore: "Nutstore (坚果云)"
            case .koofr: "Koofr"
            case .pCloud: "pCloud"
            case .yandexDisk: "Yandex Disk"
            case .infiniCloud: "InfiniCLOUD"
            case .nextcloud: "Nextcloud"
            case .synology: "Synology"
            case .ownCloud: "ownCloud"
            case .qnap: "QNAP"
            case .openList: "OpenList"
            case .seafile: "Seafile"
        }
    }

    var imageAssetName: String {
        switch self {
            case .nutstore: "CloudStorage/Nutstore"
            case .koofr: "CloudStorage/Koofr"
            case .pCloud: "CloudStorage/PCloud"
            case .yandexDisk: "CloudStorage/YandexDisk"
            case .infiniCloud: "CloudStorage/InfiniCloud"
            case .nextcloud: "CloudStorage/Nextcloud"
            case .synology: "CloudStorage/Synology"
            case .ownCloud: "CloudStorage/OwnCloud"
            case .qnap: "CloudStorage/QNAP"
            case .openList: "CloudStorage/OpenList"
            case .seafile: "CloudStorage/Seafile"
        }
    }
}

enum WebDAVServiceIdentity {
    static func imageAssetName(for accountDisplayName: String?) -> String? {
        service(forAccountDisplayName: accountDisplayName)?.imageAssetName
    }

    static func service(for serverURL: URL) -> WebDAVService? {
        guard let host = serverURL.host?.lowercased() else {
            return nil
        }

        if host == "dav.jianguoyun.com" || host.hasSuffix(".jianguoyun.com") {
            return .nutstore
        }

        if host == "app.koofr.net" {
            return .koofr
        }

        if host == "webdav.pcloud.com" || host == "ewebdav.pcloud.com" {
            return .pCloud
        }

        if host == "webdav.yandex.ru" || host == "webdav.yandex.com" {
            return .yandexDisk
        }

        if host.hasSuffix(".teracloud.jp") || host.hasSuffix(".infini-cloud.net") {
            return .infiniCloud
        }

        if host.hasSuffix(".synology.me") {
            return .synology
        }

        if host.hasSuffix(".myqnapcloud.com") {
            return .qnap
        }

        if serverURL.pathComponents.contains(where: {
            $0.caseInsensitiveCompare("seafdav") == .orderedSame
        }) {
            return .seafile
        }

        return nil
    }

    static func displayName(
        for serverURL: URL,
        detectedService: WebDAVService? = nil
    ) -> String {
        if let service = detectedService ?? service(for: serverURL) {
            return service.displayName
        }
        return serverURL.host?.lowercased() ?? "WebDAV"
    }

    static func accountDisplayName(
        serverURL: URL,
        username: String,
        detectedService: WebDAVService? = nil
    ) -> String {
        "\(displayName(for: serverURL, detectedService: detectedService)) · \(username)"
    }

    private static func service(forAccountDisplayName displayName: String?) -> WebDAVService? {
        guard let displayName else { return nil }
        return WebDAVService.allCases.first { displayName.hasPrefix($0.displayName) }
    }
}
