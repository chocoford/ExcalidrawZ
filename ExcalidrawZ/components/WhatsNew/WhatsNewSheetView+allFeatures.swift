//
//  WhatsNewSheetView+allFeatures.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI

extension WhatsNewView {
    @MainActor @ViewBuilder
    func featuresContent() -> some View {
        WhatsNewFeatureRow(
            title: "Live Collaboration",
            description: "",
            icon: Image(systemSymbol: .person2CropSquareStack)
        )
        
        
#if os(iOS)
        
        if UIDevice().userInterfaceIdiom == .pad {
            
        } else if UIDevice().userInterfaceIdiom == .phone {
            
        }
#endif
    }
    
    
    @MainActor @ViewBuilder
    func allFeaturesList() -> some View {
        VStack {
            // Navigation Back button
            if #available(macOS 13.0, iOS 16.0, *) {} else {
                HStack {
                    Button {
                        route = nil
                    } label: {
                        Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(4)
                
                Divider()
            }
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            featuresContent()
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                    // MARK: - v1.3.1
                    VStack(alignment: .leading, spacing: 10) {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewSubgroupsSupportTitle),
                            description: .localizable(.whatsNewSubgroupsSupportDescription)
                        ) {
                            Image(systemSymbol: .listBulletIndent)
                                .resizable()
                                .scaledToFit()
                                .padding(.leading, 2)
                        }
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewSupportLocalFoldersTitle),
                            description: .localizable(.whatsNewSupportLocalFoldersDescription),
                            icon: Image(systemSymbol: .folder)
                        )
                        
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewSupportMathTitle),
                            description: .localizable(.whatsNewSupportMathDescription),
                            icon: Image(systemSymbol: .xSquareroot)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewNewDrawFromClipboardTitle),
                            description: .localizable(.whatsNewNewDrawFromClipboardDescription),
                            icon: Image(systemSymbol: .docOnClipboard)
                        )
                        
                        
                #if os(iOS)
                        if #available(iOS 17.0, *) {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewApplePencilToolbarTitle),
                                description: .localizable(.whatsNewApplePencilToolbarDescrition),
                                icon: Image(systemSymbol: .applepencilTip)
                            )
                        } else {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewApplePencilToolbarTitle),
                                description: .localizable(.whatsNewApplePencilToolbarDescrition),
                                icon: Image(systemSymbol: .pencilTip)
                            )
                        }
                #endif
                    }
                    // MARK: - v1.2.9
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewFallbackExcalifontTitle),
                                description: .localizable(.whatsNewFallbackExcalifontDescription),
                                icon: Image(systemSymbol: .characterCursorIbeam)
                            ) {
                                if let url = Bundle.main.url(forResource: "Fallback Excalifont 720p", withExtension: "mov") {
                                    if #available(macOS 13.0, iOS 16.0, *) {
                                        NavigationLink(value: Route.video(url)) {
                                            WhatsNewRowMediaPreviewView(url: url)
                                        }
                                        .buttonStyle(.borderless)
                                    } else {
                                        Button {
                                            route = .video(url)
                                        } label: {
                                            WhatsNewRowMediaPreviewView(url: url)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewMoreToolsSupportTitle),
                                description: .localizable(.whatsNewMoreToolsSupportDescription)
                            ) {
                                if #available(macOS 15.0, iOS 18.0, *) {
                                    Image(systemName: "xmark.triangle.circle.square")
                                        .resizable()
                                } else {
                                    Image(systemSymbol: .shippingbox)
                                        .resizable()
                                }
                            }
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewLosslessPDFExportTitle),
                                description: .localizable(.whatsNewLosslessPDFExportDescription),
                                icon: Image(systemSymbol: .scribble)
                            )
                        } header: {
                            Text("v1.2.9")
                                .font(.headline)
                            Divider()
                        }
                    }
                    // MARK: - v1.2.8
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewMoreI18nSupportTitle),
                                description: .localizable(.whatsNewMoreI18nSupportDescription),
                                icon: Image(systemSymbol: .docRichtext)
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("v1.2.8")
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                    // MARK: - v1.2.7
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewMultiTouchTitle),
                                // 当使用两根手指触碰屏幕，将进行一次undo操作；当使用三根手指触碰屏幕，将进行一次redo操作
                                description: .localizable(.whatsnewMultiTouchDescription),
                                icon: Image(systemSymbol: .handTapFill)
                            )
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewExportPDFTitle),
                                description: .localizable(.whatsnewExportPDFDescription),
                                icon: Image(systemSymbol: .docRichtext)
                            )
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewExportImageWithoutBackgroundTitle),
                                description: .localizable(.whatsnewExportImageWithoutBackgroundDescription),
                                icon: Image(systemSymbol: .photoOnRectangle)
                            )
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewApplePencilSupportTitle),
                                description: .localizable(.whatsnewApplePencilSupportDescription),
                                icon: Image(systemSymbol: .applepencil)
                            )
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsnewAccesibleWithoutNetworkTitle),
                                description: .localizable(.whatsnewAccesibleWithoutNetworkDescription),
                                icon: Image(systemSymbol: .wifiSlash)
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("v1.2.7")
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                    // MARK: - v1.2.3
                    VStack(alignment: .leading, spacing: 10) {
                        Section {
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewItemMultiplatformTitle),
                                description: .localizable(.whatsNewItemMultiplatformDescription)
                            ) {
                                if #available(macOS 13.0, iOS 16.1, *) {
                                    Image(systemSymbol: .macbookAndIphone)
                                        .resizable()
                                } else {
                                    Image(systemSymbol: .ipadAndIphone)
                                        .resizable()
                                }
                            }
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewItemPreventImageAutoInvertTitle),
                                description: .localizable(.whatsNewItemPreventImageAutoInvertDescription),
                                icon: Image(systemSymbol: .photoOnRectangle)
                            )
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewItemFileLoadPerformanceTitle),
                                description: .localizable(.whatsNewItemFileLoadPerformanceDescription),
                                icon: Image(systemSymbol: .timer)
                            )
                            
                            WhatsNewFeatureRow(
                                title: .localizable(.whatsNewIcloudSyncTitle),
                                description: .localizable(.whatsNewIcloudSyncDescription),
                                icon: Image(systemSymbol: .icloud)
                            )
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("v1.2.3")
                                    .font(.headline)
                                Divider()
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
                .padding(.horizontal, containerHorizontalSizeClass == .compact ? 10 : 40)
            }
#if os(macOS)
            .frame(width: navigationSize.width, height: max(0, navigationSize.height - 40))
#endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ/blob/main/CHANGELOG.md")!) {
                    HStack(spacing: 2) {
                        Text("Change Log")
                        Image(systemSymbol: .arrowRight)
                    }
                }
            }
        }
    }
    
}

#Preview {
    WhatsNewView()
}
