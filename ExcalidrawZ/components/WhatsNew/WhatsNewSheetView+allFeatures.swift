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
        // 不能只有一行，不知道为啥一定报错
        
        WhatsNewFeatureRow(
            title: "AI for ExcalidrawZ",
            description: "Chat with AI directly in ExcalidrawZ to read your canvas, edit elements, navigate drawings, use library items, attach images, revise previous prompts, and safely revert AI-made canvas changes. New AI plans and credits are now available from the refreshed Paywall.",
        ) {
            Image(systemSymbol: .sparkles)
                .resizable()
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
        }
        
        WhatsNewFeatureRow(
            title: "Updated Subscription Plans",
            description: "Subscription plans have been reorganized around the new AI credit system, with clearer tiers for Starter, Pro, and Max users. You can review the updated options from the refreshed Paywall.",
        ) {
            Image(systemSymbol: .creditcard)
                .resizable()
                .symbolRenderingMode(.multicolor)
        }
    }
    
    
    @MainActor @ViewBuilder
    func allFeaturesList() -> some View {
        VStack(spacing: 0) {
            // Navigation Back button
#if os(macOS)
            if #available(macOS 13.0, *) {
                HStack {
                    Button {
                        if !navigationPath.isEmpty {
                            navigationPath.removeLast()
                        }
                    } label: {
                        Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                    }
                    .modernButtonStyle(style: .glass, shape: .circle)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            } else {
                HStack {
                    Button {
                        route = nil
                    } label: {
                        Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                    }
                    .modernButtonStyle(style: .glass, shape: .circle)

                    Spacer()
                }
                .padding(4)
            }
#else
            if #available(iOS 16.0, *) {} else {
                HStack {
                    Button {
                        route = nil
                    } label: {
                        Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                    }
                    .modernButtonStyle(style: .glass, shape: .circle)
                    
                    Spacer()
                }
                .padding(4)
            }
#endif
            
            // Content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    WhatsNewVersionSection(
                        version: Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
                    ) {
                        featuresContent()
                    }
                    
                    // MARK: - v1.7.4
                    WhatsNewVersionSection(version: "v1.7.4") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewTabbedInspectorTitle),
                            description: .localizable(.whatsNewTabbedInspectorDescription),
                            icon: Image(systemSymbol: .sidebarRight)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewCanvasSearchTitle),
                            description: .localizable(.whatsNewCanvasSearchDescription),
                            icon: Image(systemSymbol: .magnifyingglass)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewCanvasPreferencesTitle),
                            description: .localizable(.whatsNewCanvasPreferencesDescription),
                            icon: Image(systemSymbol: .sliderHorizontal3)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewLassoToolTitle),
                            description: .localizable(.whatsNewLassoToolDescription),
                            icon: Image(systemSymbol: .selectionPinInOut)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewLibraryWorkflowOverhaulTitle),
                            description: .localizable(.whatsNewLibraryWorkflowOverhaulDescription),
                            icon: Image(systemSymbol: .book)
                        )
                    }
                    
                    // MARK: - v1.7.3
                    WhatsNewVersionSection(version: "v1.7.3") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewUpdateExcalidrawCoreTitle),
                            description: .localizable(.whatsNewBetterDarkModeDescription),
                        ) {
                            ExcalidrawIconView()
                                .frame(height: 36)
                        }

                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewReducedAppSizeTitle),
                            description: .localizable(
                                .whatsNewReducedAppSizeDescription(
                                    Decimal(0.3).formatted(.percent.precision(.fractionLength(0)))
                                )
                            ),
                            icon: Image(systemSymbol: .externaldrive)
                        )
                    }
                    
                    // MARK: - v1.7.0
                    WhatsNewVersionSection(version: "v1.7.0") {
#if os(iOS)
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewRedesignUITitle),
                            description: .localizable(.whatsNewRedesignUIDescription),
                            icon: Image(systemSymbol: .macwindow)
                        )
#endif
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewMoveContentToICloudDriveTitle),
                            description: .localizable(.whatsNewMoveContentToICloudDriveDescription),
                            icon: Image(systemSymbol: .externaldriveConnectedToLineBelow)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewImportPDFTitle),
                            description: .localizable(.whatsNewImportPDFDescription),
                            icon: {
                                if #available(macOS 15.0, iOS 18.0, *) {
                                    Image(systemSymbol: .richtextPage)
                                } else {
                                    Image(systemSymbol: .docRichtext)
                                }
                            }()
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewCustomDrawingSettingsTitle),
                            description: .localizable(.whatsNewCustomDrawingSettingsDescription),
                            icon: Image(systemSymbol: .gearshape2)
                        )
                    }
                    
                    // MARK: - v1.6.1
                    WhatsNewVersionSection(version: "v1.6.1") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewUpdateExcalidrawCoreTitle),
                            description: .localizable(.whatsNewUpdateExcalidrawCoreDescription)
                        ) {
                            ExcalidrawIconView()
                                .frame(height: 36)
                        }
                    }

#if os(macOS)
                    // MARK: - v1.6.0
                    WhatsNewVersionSection(version: "v1.6.0") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewRedesignUITitle),
                            description: .localizable(.whatsNewRedesignUIDescription),
                            icon: Image(systemSymbol: .macwindow)
                        )
                        
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewEnhanceInteractiveExperienceTitle),
                            description: .localizable(.whatsNewEnhanceInteractiveExperienceDescription),
                            icon: Image(systemSymbol: .cursorarrowMotionlines)
                        )
                    }
                    // MARK: - v1.5.1
                    WhatsNewVersionSection(version: "v1.5.1") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewCustomFontTitle),
                            description: .localizable(.whatsNewCustomFontDescription),
                            icon: Image(systemSymbol: .character)
                        )
                    }
#endif

                    // MARK: - v1.4.5
                    WhatsNewVersionSection(version: "v1.4.5") {
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewLiveCollaborationCompabilityTitle),
                            description: .localizable(.whatsNewLiveCollaborationCompabilityDescription),
                            icon: Image(systemSymbol: .person2CropSquareStack)
                        )
                #if os(macOS)
                        WhatsNewFeatureRow(
                            title: .localizable(.whatsNewSidebarFilesMultiSelectTitle),
                            description: .localizable(.whatsNewSidebarFilesMultiSelectDescription),
                            icon: Image(systemSymbol: .filemenuAndSelection)
                        )
                #endif
                    }
                    
                    // MARK: - v1.4.4
                    WhatsNewVersionSection(version: "v1.4.4") {
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
                            if let url = URL(string: "https://pub-2983ae3d3c894bd08530707492e919db.r2.dev/Fallback Excalifont 720p.mov") {
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

#if os(macOS)
                HStack {
                    Spacer()

                    changeLogLink()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
#endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                changeLogLink()
            }
        }
#endif
    }

    @MainActor @ViewBuilder
    private func changeLogLink() -> some View {
        Link(destination: URL(string: "https://github.com/chocoford/ExcalidrawZ/blob/main/CHANGELOG.md")!) {
            HStack(spacing: 2) {
                Text("Change Log")
                Image(systemSymbol: .arrowRight)
            }
        }
        .hoverCursor(.link)
    }
}

struct WhatsNewVersionSection: View {
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass

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
                    .padding(.horizontal, containerHorizontalSizeClass == .compact ? 10 : 40)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(version)
                        .font(.headline)
                        .padding(.horizontal, containerHorizontalSizeClass == .compact ? 10 : 20)
                    Divider()
                }
            }
        }
    }
}

#Preview {
    WhatsNewView()
}
