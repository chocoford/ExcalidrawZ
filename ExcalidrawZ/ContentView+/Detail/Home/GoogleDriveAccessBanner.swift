//
//  GoogleDriveAccessBanner.swift
//  ExcalidrawZ
//

import SwiftUI

struct GoogleDriveAccessBanner: View {
    let folder: CloudStorageFolderReference
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(.top, 2)
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    explanation
                    authorizationButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    explanation
                    authorizationButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localizable: .generalButtonClose))
            .accessibilityLabel(Text(.localizable(.generalButtonClose)))
            .accessibilityIdentifier("google-drive-access-hint-close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14)
            let warningTint = Color.yellow.opacity(0.16)
            if #available(macOS 26.0, iOS 26.0, *) {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(warningTint), in: shape)
            } else {
                shape.fill(warningTint)
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.localizable(.cloudStorageGoogleDriveAuthorizeMore))
                .font(.callout.weight(.semibold))
            Text(.localizable(.cloudStorageGoogleDriveAccessExplanation))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorizationButton: some View {
        GoogleDriveAuthorizationButton(location: folder.location, parentID: folder.itemID) { isWorking in
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(.localizable(.cloudStorageGoogleDriveAuthorizeMoreAction))
            }
        }
        .buttonStyle(.bordered)
    }
}
