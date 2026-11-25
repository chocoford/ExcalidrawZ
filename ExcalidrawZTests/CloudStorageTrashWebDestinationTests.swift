import Foundation
import XCTest
@testable import ExcalidrawZ

final class CloudStorageTrashWebDestinationTests: XCTestCase {
    private func destination(
        _ providerID: CloudStorageProviderID,
        root: String = "root",
        accountName: String? = nil
    ) -> CloudStorageTrashWebDestination? {
        CloudStorageTrashWebDestination.destination(
            for: CloudStorageLocation(
                providerID: providerID,
                accountID: .init(rawValue: "account"),
                rootItemID: .init(rawValue: root),
                displayName: "Drawings"
            ),
            accountDisplayName: accountName
        )
    }

    func testProviderDestinationsDoNotDependOnTheLinkedFolderPath() {
        XCTAssertEqual(destination(.microsoftOneDrive), .oneDrive)
        for (provider, address) in [
            (CloudStorageProviderID.googleDrive, "https://drive.google.com/drive/trash"),
            (.dropbox, "https://www.dropbox.com/deleted_files"),
            (.box, "https://app.box.com/trash")
        ] {
            XCTAssertEqual(destination(provider), .website(URL(string: address)!))
        }
        XCTAssertNil(destination(.init(rawValue: "unknown")))
    }

    func testPersonalOneDriveKeepsOnlyItsAccountHint() throws {
        let source = URL(string: "https://user:password@onedrive.live.com/?cid=0123456789ABCDEF&id=folder&authkey=secret#fragment")!
        let result = try XCTUnwrap(CloudStorageTrashWebDestination.oneDriveURL(for: source))
        XCTAssertEqual(result.absoluteString, "https://onedrive.live.com/?id=root&qt=recyclebin&cid=0123456789ABCDEF")
        XCTAssertEqual(
            CloudStorageTrashWebDestination.oneDriveURL(for: URL(string: "https://onedrive.live.com/?cid=invalid")!)?.absoluteString,
            "https://onedrive.live.com/?id=root&qt=recyclebin"
        )
    }

    func testBusinessOneDriveUsesItsOwnPersonalSite() {
        let source = URL(string: "https://tenant-my.sharepoint.com/personal/alex_example_com/Documents/Drawings?token=secret")!
        XCTAssertEqual(
            CloudStorageTrashWebDestination.oneDriveURL(for: source)?.absoluteString,
            "https://tenant-my.sharepoint.com/personal/alex_example_com/_layouts/15/RecycleBin.aspx"
        )
    }

    func testSharePointSitePathsAndSharingURLs() {
        for (path, sitePath) in [
            ("sites/Design%20Team/Shared%20Documents/Drawings", "sites/Design%20Team/"),
            ("teams/Design/Documents/Drawings", "teams/Design/"),
            (":f:/r/sites/Design/Documents/Drawings", "sites/Design/"),
            ("Shared%20Documents/Drawings", "")
        ] {
            XCTAssertEqual(
                CloudStorageTrashWebDestination.oneDriveURL(for: URL(string: "https://tenant.sharepoint.com/" + path)!)?.absoluteString,
                "https://tenant.sharepoint.com/" + sitePath + "_layouts/15/RecycleBin.aspx"
            )
        }
    }

    func testUnresolvableOneDriveURLsDoNotFallBackToAnotherAccount() {
        for address in [
            "https://tenant.sharepoint.com.evil.example/sites/Design",
            "https://evilsharepoint.com/sites/Design",
            "https://onedrive.live.com.evil.example/",
            "https://tenant.sharepoint.com/sites",
            "https://tenant.sharepoint.com/:f:/s/Design/sharingToken",
            "file:///personal/alex/",
            "ftp://tenant.sharepoint.com/sites/Design"
        ] {
            XCTAssertNil(CloudStorageTrashWebDestination.oneDriveURL(for: URL(string: address)!), address)
        }
    }

    func testNextcloudPreservesItsInstallationPathAndDropsCredentials() {
        XCTAssertEqual(
            destination(
                .webDAV,
                root: "https://alex:password@cloud.example:8443/My%20Cloud/remote.php/dav/files/alex/Drawings?token=secret#fragment",
                accountName: "Nextcloud · alex"
            ),
            .website(URL(string: "https://cloud.example:8443/My%20Cloud/index.php/apps/files/trashbin")!)
        )
        XCTAssertNil(destination(.webDAV, root: "https://cloud.example/dav/", accountName: "Nextcloud · alex"))
        XCTAssertNil(destination(.webDAV, root: "https://cloud.example/remote.php/dav/files/alex/"))
        XCTAssertNil(destination(.webDAV, root: "https://cloud.example/dav/"))
    }

    func testPCloudSupportsBothRegions() {
        for host in ["webdav.pcloud.com", "ewebdav.pcloud.com"] {
            XCTAssertEqual(
                destination(.webDAV, root: "https://" + host + "/Drawings/"),
                .website(URL(string: "https://my.pcloud.com/#page=trash")!)
            )
        }
    }
}
