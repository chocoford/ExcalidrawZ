//
//  FontsSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 6/28/25.
//

import SwiftUI

import ChocofordUI

#if os(macOS)
struct FontsSettingsView: View {
    var body: some View {
        if #available(macOS 13.0, *) {
            Form {
                content()
            }.formStyle(.grouped)
        } else {
            ScrollView {
                content()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        MultiFontPickerView()
    }
}

/// A view that manages a list of selected fonts, persisted via AppStorage.
struct MultiFontPickerView: View {
    @AppStorage("addedFontsData") private var addedFontsData: Data = Data()
    
    init() {}
    
    @State private var showPicker = false
    @State private var tempFont: String = NSFontManager.shared.availableFontFamilies.first ?? ""

    @State private var addedFonts: Set<String> = []
    @State private var selectedFonts: Set<String> = []
    
    @State private var selectStartFont: String?
    
    @State private var keyboardMonitor: Any?

    var body: some View {
        Section {
            VStack(spacing: 1) {
                if addedFonts.isEmpty {
                    Text(localizable: .settingsFontsAddedFontsPlaceholder)
                        .font(.title.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 200, alignment: .center)
                } else {
                    let fonts = Array(addedFonts.sorted())
                    ForEach(fonts, id: \.self) { font in
                        let isSelected = selectedFonts.contains(font)
                        
                        Text(font)
                            .font(.custom(font, size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                isSelected ? Color.accentColor : Color.clear,
                                in: Rectangle()
                            )
                            .foregroundStyle(
                                isSelected
                                ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(HierarchicalShapeStyle.primary)
                            )
                            .onTapGesture {
                                defer {
                                    if selectedFonts.count <= 1 {
                                        selectStartFont = font
                                    }
                                }
                                
                                if NSEvent.modifierFlags.contains(.command) {
                                    selectedFonts.insertOrRemove(font)
                                } else if NSEvent.modifierFlags.contains(.shift) {
                                    guard let selectStart = selectStartFont,
                                          let startIdx = fonts.firstIndex(of: selectStart),
                                          let endIdx = fonts.firstIndex(of: font) else {
                                        return
                                    }
                                    let range = startIdx <= endIdx
                                        ? startIdx...endIdx
                                        : endIdx...startIdx
                                    let sliceItems = fonts[range]
                                    let sliceSet = Set(sliceItems)
                                    selectedFonts = sliceSet
                                } else {
                                    selectedFonts = [font]
                                }
                            }
                        
                        if fonts.last != font {
                            Divider()
                        }
                    }
                }
            }
        } header: {
            Text(localizable: .settingsFontsAddedFontsTitle)
        } footer: {
            HStack {
                if let fontBookURL: URL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FontBook") {
                    Button {
                        NSWorkspace.shared.open(fontBookURL)
                    } label: {
                        Text(localizable: .settingsFontsAddedFontsButtonOpenFontBook)
                    }
                    .modernButtonStyle(shape: .modern)
                }
                
                Spacer()
                SwiftUI.Group {
                    Button {
                        for selected in selectedFonts {
                            addedFonts.remove(selected)
                        }
                    } label: {
                        Image(systemSymbol: .minus)
                    }
                    
                    Button {
                        tempFont = NSFontManager.shared.availableFontFamilies.first ?? ""
                        showPicker = true
                    } label: {
                        Image(systemSymbol: .plus)
                    }
                }
                .buttonStyle(.text(square: true))
            }
        }
        .sheet(isPresented: $showPicker) {
            FontSelectorView(selections: $addedFonts)
        }
        .onChange(of: addedFonts) { newValue in
            addedFontsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
        .watchImmediately(of: addedFontsData) { newValue in
            addedFonts = (try? JSONDecoder().decode(Set<String>.self, from: newValue)) ?? []
        }
        .onAppear {
            // Backspace to remove selected font
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                guard event.keyCode == 51 else { return event }
                for selected in selectedFonts {
                    remove(selected)
                }
                return event
            }
        }
        .onDisappear {
            if let keyboardMonitor = keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
            }
        }
    }

    private func remove(_ font: String) {
        addedFonts.remove(font)
        selectedFonts.remove(font)

    }
}



/// A SwiftUI view to pick a single font from the system list.
/// Used within a sheet for adding fonts.
struct FontSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Binding var selections: Set<String>
    
    @State private var searchText: String = ""
    private let fonts: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    @State private var newSelections: Set<String> = []
    
    enum DisplayType: Hashable {
        case all
        case selected
    }
    
    @State private var displayType: DisplayType = .all

    private var filteredFonts: [String] {
        guard !searchText.isEmpty else { return fonts }
        return fonts.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var filteredSelections: [String] {
        guard !searchText.isEmpty else { return Array(newSelections).sorted() }
        return Array(newSelections).filter { $0.localizedCaseInsensitiveContains(searchText) }.sorted()
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(localizable: .settingsFontsAddedFontsAddTitle)
                .font(.title2)
                .bold()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            TextField(.localizable(.searchFieldPropmtText), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
            
            Picker(selection: $displayType) {
                Text(localizable: .settingsFontsAddedFontsCategoryAll)
                    .tag(DisplayType.all)
                Text(localizable: .settingsFontsAddedFontsCategorySelected)
                    .tag(DisplayType.selected)
            } label: {
                
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(
                        displayType == .all ? filteredFonts : filteredSelections,
                        id: \.self
                    ) { font in
                        Hover { isHovered in
                            HStack {
                                Text(font)
                                    .font(.custom(font, size: 16))
                                Spacer()
                                if newSelections.contains(font) {
                                    Image(systemSymbol: .checkmark)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        isHovered
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                                        : AnyShapeStyle(Color.clear)
                                    )
                            }
                            .onTapGesture {
                                newSelections.insertOrRemove(font)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 300)
            .animation(.default, value: displayType)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(localizable: .generalButtonCancel)
                        .frame(width: 80)
                }
                Button {
                    selections = newSelections
                    dismiss()
                } label: {
                    Text(localizable: .generalButtonDone)
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            self.newSelections = selections
        }
    }
}

#Preview {
    FontsSettingsView()
}
#endif
