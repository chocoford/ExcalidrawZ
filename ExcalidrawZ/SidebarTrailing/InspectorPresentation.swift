//
//  InspectorPresentation.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/3/26.
//

import SwiftUI
import CoreData

import SFSafeSymbols
import ChocofordEssentials
import ChocofordUI
import UniformTypeIdentifiers

struct InspectorPresentationModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @EnvironmentObject private var appPreference: AppPreference
    @EnvironmentObject private var layoutState: LayoutState

    @State private var librariesToImport: [ExcalidrawLibrary] = []

    var shouldUseFloatingInspector: Bool {
        if appPreference.inspectorLayout == .floatingBar {
            return true
        } else if #available(iOS 26.0, *) {
            #if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .pad {
                /// inspector cause sidebar layout wierd in iPad
                return true
            } else {
                return false
            }
            #else
            return false
            #endif
        } else {
            return false
        }
    }

    func body(content: Content) -> some View {
        ZStack {
            if shouldUseFloatingInspector {
                floatingInspector(content: content)
            } else if containerHorizontalSizeClass == .compact {
                content
                    .sheet(isPresented: $layoutState.isInspectorPresented) {
                        inspectorContent()
                    }
            } else if #available(macOS 14.0, iOS 17.0, *) {
                content
                    .inspector(isPresented: $layoutState.isInspectorPresented) {
                        inspectorContent()
                            .inspectorColumnWidth(min: 280, ideal: 350, max: 400)
                    }
            } else {
                floatingInspector(content: content)
            }
        }
        // Island overlay lives on `ExcalidrawEditor` (not here) — the editor
        // is the actual frame the user perceives as "the canvas", and bottom-
        // center should be the canvas's bottom-center, not the whole window's.
        .modifier(ExcalidrawLibraryImporter(items: $librariesToImport))
    }

    /// Picks the view shown inside the inspector based on the active tab.
    @MainActor @ViewBuilder
    private func inspectorContent() -> some View {
        if layoutState.isInspectorPresented {
            switch layoutState.activeInspectorTab {
                case .aiChat:
                    AIChatView()
                case .library:
                    LibraryView(librariesToImport: $librariesToImport)
                case .history:
                    FileHistoryInspectorContent()
                case .preference:
                    CanvasSettingsInspectorContent()
                case .search:
                    SearchInspectorContent()
#if DEBUG
                case .debug:
                    DebugPanelView()
#endif
            }
        }
    }

    private var inspectorTitle: String {
        switch layoutState.activeInspectorTab {
            case .aiChat:
                "AI Chat"
            case .library:
                String(localizable: .librariesTitle)
            case .history:
                String(localizable: .checkpoints)
            case .preference:
                String(localizable: .canvasPreferencesTitle)
            case .search:
                String(localizable: .searchButtonTitle)
#if DEBUG
            case .debug:
                "Debug"
#endif
        }
    }

    @MainActor @ViewBuilder
    private func floatingInspector(content: Content) -> some View {
        ZStack {
            content
            HStack {
                Spacer()
                if layoutState.isInspectorPresented {
                    VStack {
                        Text(inspectorTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)

                        inspectorContent()
                    }
                    .frame(minWidth: 240, idealWidth: 250, maxWidth: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.background)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
#if os(macOS)
                                .shadow(radius: 4)
#endif
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .shadow(radius: 4)
                        }
                    }
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut, value: layoutState.isInspectorPresented)
#if os(macOS)
            .padding(.top, 10)
            .padding(.bottom, 40)
#else
            .padding(.bottom, 10)
#endif
            .padding(.horizontal, 10)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .topTrailing) {
            if layoutState.isInspectorPresented {
                ExcalidrawTrailingControls()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut, value: layoutState.isInspectorPresented)
    }
}

#if os(macOS)
/// Renders the title that appears at the top of the inspector chrome in sidebar mode.
/// The placement gymnastics are needed to push the toggle to the right and center the title across macOS versions.
struct InspectorHeaderToolbar: ToolbarContent {
    let title: String
    let isInspectorPresented: Bool

    var body: some ToolbarContent {

        /// This is the key to make sidebar toggle at the right side.
        /// The `status` is work well in macOS 15.0+. But not well in macOS 14.0
        ToolbarItemGroup(placement:  .status) {
            if isInspectorPresented {
                if #available(macOS 15.0, iOS 18.0, *) {} else {
                    Spacer()
                }
                Text(title)
                    .foregroundStyle(.secondary)
                    .font(.headline)
                    .padding(.horizontal, 8)
                if #available(macOS 15.0, iOS 18.0, *) {} else {
                    Spacer()
                }
            } else {
                if #available(macOS 26.0, *) {} else {
                    Color.clear
                        .frame(width: 1)
                }
            }
        }
        
    }
}
#endif
