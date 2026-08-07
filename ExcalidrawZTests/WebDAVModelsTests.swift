//
//  WebDAVModelsTests.swift
//  ExcalidrawZTests
//

import XCTest
@testable import ExcalidrawZ

final class WebDAVModelsTests: XCTestCase {
    func testRecognizesNutstoreService() throws {
        let url = try XCTUnwrap(URL(string: "https://dav.jianguoyun.com/dav/"))

        XCTAssertEqual(
            WebDAVServiceIdentity.displayName(for: url),
            "Nutstore (坚果云)"
        )
        XCTAssertEqual(
            WebDAVServiceIdentity.accountDisplayName(
                serverURL: url,
                username: "person@example.com"
            ),
            "Nutstore (坚果云) · person@example.com"
        )
    }

    func testUsesHostForUnknownWebDAVService() throws {
        let url = try XCTUnwrap(URL(string: "https://cloud.example.com/remote.php/dav/"))

        XCTAssertEqual(
            WebDAVServiceIdentity.displayName(for: url),
            "cloud.example.com"
        )
    }

    func testRecognizesSeafileWebDAVPath() throws {
        let url = try XCTUnwrap(URL(string: "https://cloud.example.com/seafdav/"))

        XCTAssertEqual(WebDAVServiceIdentity.service(for: url), .seafile)
        XCTAssertEqual(WebDAVServiceIdentity.displayName(for: url), "Seafile")
    }

    func testRecognizesNextcloudStatusResponse() throws {
        let probe = WebDAVServiceProbe(
            kind: .nextcloudStatus,
            url: try XCTUnwrap(URL(string: "https://cloud.example.com/status.php"))
        )
        let response = WebDAVServiceProbeResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"installed":true,"productname":"Nextcloud"}"#.utf8)
        )

        XCTAssertEqual(
            WebDAVServiceFingerprint.service(in: response, for: probe),
            .nextcloud
        )
    }

    func testRecognizesOwnCloudStatusResponse() throws {
        let probe = WebDAVServiceProbe(
            kind: .nextcloudStatus,
            url: try XCTUnwrap(URL(string: "https://cloud.example.com/status.php"))
        )
        let response = WebDAVServiceProbeResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"installed":true,"productname":"ownCloud"}"#.utf8)
        )

        XCTAssertEqual(
            WebDAVServiceFingerprint.service(in: response, for: probe),
            .ownCloud
        )
    }

    func testRecognizesOpenListSettingsResponse() throws {
        let probe = WebDAVServiceProbe(
            kind: .openListSettings,
            url: try XCTUnwrap(URL(string: "https://cloud.example.com/api/public/settings"))
        )
        let response = WebDAVServiceProbeResponse(
            statusCode: 200,
            headers: [:],
            body: Data(
                #"{"code":200,"data":{"site_title":"Drawings","version":"v4.1.0"}}"#.utf8
            )
        )

        XCTAssertEqual(
            WebDAVServiceFingerprint.service(in: response, for: probe),
            .openList
        )
    }

    func testRecognizesSeafilePingResponse() throws {
        let probe = WebDAVServiceProbe(
            kind: .seafilePing,
            url: try XCTUnwrap(URL(string: "https://cloud.example.com/api2/ping/"))
        )
        let response = WebDAVServiceProbeResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#""pong""#.utf8)
        )

        XCTAssertEqual(
            WebDAVServiceFingerprint.service(in: response, for: probe),
            .seafile
        )
    }

    func testDecodesLegacyCredentialWithoutServiceFingerprint() throws {
        let data = Data(
            #"{"accountID":"account","displayName":"cloud.example.com · user","serverURL":"https:\/\/cloud.example.com\/dav\/","username":"user","password":"password"}"#.utf8
        )

        let credential = try JSONDecoder().decode(WebDAVCredential.self, from: data)

        XCTAssertNil(credential.service)
        XCTAssertEqual(credential.cloudStorageAccount.displayName, "cloud.example.com · user")
    }

    func testNormalizesCollectionURLAndRemovesQuery() throws {
        let result = try WebDAVURL.normalizedServerURL(
            XCTUnwrap(URL(string: "https://dav.example.com/files/user?token=ignored#fragment"))
        )

        XCTAssertEqual(result.absoluteString, "https://dav.example.com/files/user/")
    }

    func testRejectsInsecureRemoteServerURL() throws {
        XCTAssertThrowsError(
            try WebDAVURL.normalizedServerURL(
                XCTUnwrap(URL(string: "http://dav.example.com/files"))
            )
        )
    }

    func testComparesWebDAVOriginsUsingEffectivePorts() throws {
        let implicitHTTPS = try XCTUnwrap(URL(string: "https://dav.example.com/root/"))
        let explicitHTTPS = try XCTUnwrap(URL(string: "https://dav.example.com:443/other/"))
        let differentPort = try XCTUnwrap(URL(string: "https://dav.example.com:8443/root/"))
        let differentHost = try XCTUnwrap(URL(string: "https://other.example.com/root/"))

        XCTAssertTrue(WebDAVURL.hasSameOrigin(implicitHTTPS, as: explicitHTTPS))
        XCTAssertFalse(WebDAVURL.hasSameOrigin(implicitHTTPS, as: differentPort))
        XCTAssertFalse(WebDAVURL.hasSameOrigin(implicitHTTPS, as: differentHost))
    }

    func testBuildsNextcloudEndpointCandidatesFromSiteURL() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://cloud.example.com/"))

        let candidates = WebDAVURL.endpointCandidates(
            for: serverURL,
            username: "person@example.com"
        )

        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "https://cloud.example.com/",
                "https://cloud.example.com/remote.php/dav/files/person%40example.com/",
                "https://cloud.example.com/remote.php/webdav/",
            ]
        )
    }

    func testBuildsNextcloudEndpointCandidatesForSubdirectoryInstall() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://example.com/nextcloud/"))

        let candidates = WebDAVURL.endpointCandidates(
            for: serverURL,
            username: "person"
        )

        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "https://example.com/nextcloud/",
                "https://example.com/nextcloud/remote.php/dav/files/person/",
                "https://example.com/nextcloud/remote.php/webdav/",
            ]
        )
    }

    func testDoesNotNestDiscoveryUnderExistingNextcloudEndpoint() throws {
        let serverURL = try XCTUnwrap(
            URL(string: "https://cloud.example.com/remote.php/dav/files/person/")
        )

        let candidates = WebDAVURL.endpointCandidates(
            for: serverURL,
            username: "person"
        )

        XCTAssertEqual(candidates[0], serverURL)
        XCTAssertTrue(
            candidates.contains(
                try XCTUnwrap(
                    URL(string: "https://cloud.example.com/remote.php/dav/files/person/")
                )
            )
        )
        XCTAssertFalse(
            candidates.contains {
                $0.absoluteString.contains("/files/person/remote.php/")
            }
        )
    }

    func testPrefersUserFilesForDiscoveredNextcloudDAVRoot() throws {
        let serverURL = try XCTUnwrap(
            URL(string: "https://cloud.example.com/remote.php/dav/")
        )

        let candidates = WebDAVURL.endpointCandidates(
            for: serverURL,
            username: "person"
        )

        XCTAssertEqual(
            candidates.first?.absoluteString,
            "https://cloud.example.com/remote.php/dav/files/person/"
        )
    }

    func testBuildsOriginAndSubdirectoryWellKnownURLs() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://example.com/nextcloud/"))

        XCTAssertEqual(
            WebDAVURL.wellKnownEndpointURLs(for: serverURL).map(\.absoluteString),
            [
                "https://example.com/.well-known/webdav",
                "https://example.com/nextcloud/.well-known/webdav",
            ]
        )
    }

    func testBuildsNextcloudCurrentUserURLForSubdirectoryInstall() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://example.com/nextcloud/"))

        XCTAssertEqual(
            WebDAVURL.nextcloudCurrentUserURLs(for: serverURL).map(\.absoluteString),
            [
                "https://example.com/nextcloud/ocs/v1.php/cloud/user?format=json",
                "https://example.com/ocs/v1.php/cloud/user?format=json",
            ]
        )
    }

    func testBuildsNextcloudCapabilitiesURLForSubdirectoryInstall() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://example.com/nextcloud/"))

        XCTAssertEqual(
            WebDAVURL.nextcloudCapabilitiesURLs(for: serverURL).map(\.absoluteString),
            [
                "https://example.com/nextcloud/ocs/v1.php/cloud/capabilities?format=json",
                "https://example.com/ocs/v1.php/cloud/capabilities?format=json",
            ]
        )
    }

    func testResolvesServerDeclaredWebDAVRoot() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://example.com/nextcloud/"))

        XCTAssertEqual(
            WebDAVURL.resolvedServerDeclaredEndpoint(
                "remote.php/dav",
                relativeTo: serverURL
            )?.absoluteString,
            "https://example.com/nextcloud/remote.php/dav/"
        )
        XCTAssertEqual(
            WebDAVURL.resolvedServerDeclaredEndpoint(
                "/nextcloud/remote.php/webdav",
                relativeTo: serverURL
            )?.absoluteString,
            "https://example.com/nextcloud/remote.php/webdav/"
        )
    }

    func testParsesNextcloudCurrentUserID() throws {
        let response = Data(
            #"{"ocs":{"meta":{"status":"ok","statuscode":100},"data":{"id":"internal-user-id"}}}"#.utf8
        )

        XCTAssertEqual(
            WebDAVClient.nextcloudUserID(in: response),
            "internal-user-id"
        )
    }

    func testParsesNextcloudWebDAVRoot() throws {
        let response = Data(
            #"{"ocs":{"meta":{"status":"ok","statuscode":100},"data":{"capabilities":{"core":{"webdav-root":"remote.php/dav"}}}}}"#.utf8
        )

        XCTAssertEqual(
            WebDAVClient.nextcloudWebDAVRoot(in: response),
            "remote.php/dav"
        )
    }

    func testRejectsRewrittenWellKnownPathAsDAVEndpoint() throws {
        XCTAssertFalse(
            WebDAVURL.isUsableDiscoveredEndpointURL(
                try XCTUnwrap(
                    URL(string: "https://cloud.example.com/index.php/.well-known/webdav/")
                )
            )
        )
        XCTAssertTrue(
            WebDAVURL.isUsableDiscoveredEndpointURL(
                try XCTUnwrap(
                    URL(string: "https://cloud.example.com/remote.php/dav/")
                )
            )
        )
    }

    func testParsesMultiStatusResources() throws {
        let responseURL = try XCTUnwrap(URL(string: "https://dav.example.com/root/"))
        let data = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:multistatus xmlns:d="DAV:">
              <d:response>
                <d:href>/root/</d:href>
                <d:propstat>
                  <d:prop>
                    <d:displayname>Drawings</d:displayname>
                    <d:resourcetype><d:collection/></d:resourcetype>
                    <d:getetag>"folder-1"</d:getetag>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
              <d:response>
                <d:href>/root/Example.excalidraw</d:href>
                <d:propstat>
                  <d:prop>
                    <d:displayname>Example.excalidraw</d:displayname>
                    <d:resourcetype/>
                    <d:getcontenttype>application/json</d:getcontenttype>
                    <d:getcontentlength>128</d:getcontentlength>
                    <d:getlastmodified>Wed, 05 Aug 2026 01:02:03 GMT</d:getlastmodified>
                    <d:getetag>"file-1"</d:getetag>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            </d:multistatus>
            """.utf8
        )

        let resources = try WebDAVMultiStatusParser(responseURL: responseURL).parse(data)

        XCTAssertEqual(resources.count, 2)
        XCTAssertTrue(resources[0].isCollection)
        XCTAssertEqual(resources[0].url.absoluteString, "https://dav.example.com/root/")
        XCTAssertFalse(resources[1].isCollection)
        XCTAssertEqual(resources[1].displayName, "Example.excalidraw")
        XCTAssertEqual(resources[1].contentLength, 128)
        XCTAssertEqual(resources[1].etag, "\"file-1\"")
        XCTAssertNotNil(resources[1].modifiedAt)
    }

    func testKeepsResourceWhenASecondaryPropstatIsNotFound() throws {
        let responseURL = try XCTUnwrap(URL(string: "https://cloud.example.com/remote.php/dav/files/person/"))
        let data = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:multistatus xmlns:d="DAV:">
              <d:response>
                <d:href>/remote.php/dav/files/person/</d:href>
                <d:propstat>
                  <d:prop>
                    <d:displayname>person</d:displayname>
                    <d:resourcetype><d:collection/></d:resourcetype>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
                <d:propstat>
                  <d:prop>
                    <d:getcontentlength/>
                    <d:getetag/>
                  </d:prop>
                  <d:status>HTTP/1.1 404 Not Found</d:status>
                </d:propstat>
              </d:response>
            </d:multistatus>
            """.utf8
        )

        let resources = try WebDAVMultiStatusParser(responseURL: responseURL).parse(data)

        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources[0].displayName, "person")
        XCTAssertTrue(resources[0].isCollection)
    }

    func testDropsCrossOriginResourcesFromMultiStatusResponse() throws {
        let responseURL = try XCTUnwrap(URL(string: "https://dav.example.com/root/"))
        let data = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:multistatus xmlns:d="DAV:">
              <d:response>
                <d:href>https://other.example.com/credential-target.excalidraw</d:href>
                <d:propstat>
                  <d:prop><d:displayname>External</d:displayname></d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            </d:multistatus>
            """.utf8
        )

        XCTAssertTrue(
            try WebDAVMultiStatusParser(responseURL: responseURL).parse(data).isEmpty
        )
    }

    func testMapsResourceToProviderNeutralItem() throws {
        let rootURL = try XCTUnwrap(URL(string: "https://dav.example.com/root/"))
        let resource = WebDAVResource(
            url: try XCTUnwrap(URL(string: "https://dav.example.com/root/Folder/")),
            displayName: "Folder",
            isCollection: true,
            contentType: nil,
            contentLength: nil,
            createdAt: nil,
            modifiedAt: nil,
            etag: "\"folder\""
        )

        let item = resource.cloudStorageItem(rootURL: rootURL)

        XCTAssertEqual(item.id.rawValue, "https://dav.example.com/root/Folder/")
        XCTAssertEqual(item.parentID?.rawValue, "https://dav.example.com/root/")
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.capabilities, .writableFolder)
    }
}
