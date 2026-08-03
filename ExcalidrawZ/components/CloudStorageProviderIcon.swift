//
//  CloudStorageProviderIcon.swift
//  ExcalidrawZ
//

import SwiftUI

struct CloudStorageProviderIcon: View {
    let providerID: CloudStorageProviderID
    let size: CGFloat

    var body: some View {
        if let imageName {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: systemImageName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var imageName: String? {
        switch providerID {
            case .microsoftOneDrive:
                return "CloudStorage/OneDrive"
            case .googleDrive:
                return "CloudStorage/GoogleDrive"
            case .dropbox:
                return "CloudStorage/Dropbox"
            case .box:
                return "CloudStorage/Box"
            default:
                return nil
        }
    }

    private var systemImageName: String {
        switch providerID {
            case .microsoftOneDrive:
                return "cloud.fill"
            case .googleDrive:
                return "triangle.fill"
            case .dropbox:
                return "shippingbox.fill"
            case .box:
                return "archivebox.fill"
            default:
                return "externaldrive.fill"
        }
    }
}
