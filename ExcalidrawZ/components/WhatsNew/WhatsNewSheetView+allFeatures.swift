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
            title: .localizable(.whatsNewLiveCollaborationTitle),
            description: .localizable(.whatsNewLiveCollaborationDescription),
            icon: Image(systemSymbol: .person2CropSquareStack)
        )

        WhatsNewFeatureRow(
            title: .localizable(.whatsNewElementLinksTitle),
            description: .localizable(.whatsNewElementLinksDescription),
            icon: Image(systemSymbol: .link)
        )

        WhatsNewFeatureRow(
            title: .localizable(.whatsNewExportDarkPNGTitle),
            description: .localizable(.whatsNewExportDarkPNGDescription),
            icon: Image(systemSymbol: .photoFillOnRectangleFill)
        )
        
#if os(iOS)
        if UIDevice().userInterfaceIdiom == .pad {
            
        } else if UIDevice().userInterfaceIdiom == .phone {
            
        }
#else
        WhatsNewFeatureRow(
            title: .localizable(.whatsNewCustomFileSortingTitle),
            description: .localizable(.whatsNewCustomFileSortingDescription),
            icon: Image(systemSymbol: {
                if #available(macOS 13.0, *) { .arrowUpAndDownTextHorizontal } else { .arrowUpAndDownCircle }
            }())
        )
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
                    WhatsNewVersionSection(
                        version: Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
                    ) {
                        featuresContent()
                    }
                    // MARK: - v1.4.1
                    WhatsNewVersionSection(version: "v1.4.1") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewSearchableAndSpotlightTitle),
                            description: .localizable(.whatsNewSearchableAndSpotlightDescription),
                            icon: Image(systemSymbol: .magnifyingglass)
                        )
#if os(macOS)
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewCustomFileSortingTitle),
                            description: .localizable(.whatsNewCustomFileSortingDescription),
                            icon: Image(systemSymbol: {
                                if #available(macOS 13.0, *) { .arrowUpAndDownTextHorizontal } else { .arrowUpAndDownCircle }
                            }())
                        )
#endif
                    }
                    // MARK: - v1.3.1
                    WhatsNewVersionSection(version: "v1.3.1") {
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
                    WhatsNewVersionSection(version: "v1.2.9") {
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
                    }
                    // MARK: - v1.2.8
                    WhatsNewVersionSection(version: "v1.2.8") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewMoreI18nSupportTitle),
                            description: .localizable(.whatsNewMoreI18nSupportDescription),
                            icon: Image(systemSymbol: .docRichtext)
                        )
                    }
                    // MARK: - v1.2.7
                    WhatsNewVersionSection(version: "v1.2.7") {
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
                    }
                    // MARK: - v1.2.3
                    WhatsNewVersionSection(version: "v1.2.3") {
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

struct WhatsNewVersionSection: View {
    var version: String
    var content: AnyView
    
    init<Content: View>(
        version: String,
        @ViewBuilder content: () -> Content
    ) {
        self.version = version
        self.content = AnyView(content())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Section {
                content
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(version)
                        .font(.headline)
                    Divider()
                }
            }
        }
    }
}

#Preview {
    WhatsNewView()
}
