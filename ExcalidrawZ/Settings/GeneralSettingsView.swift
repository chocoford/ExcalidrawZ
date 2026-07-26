//
//  GeneralSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/5/12.
//

import SwiftUI
import ChocofordUI
#if os(macOS)
import AppKit
import KeyboardShortcuts
#endif
#if os(macOS) && !APP_STORE
import Sparkle
#endif

enum FolderStructureStyle: Int {
    case disclosureGroup
    case tree
}

private struct FolderChildren: Identifiable, Hashable {
    var id = UUID()
}

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
#if os(macOS) && !APP_STORE
    @EnvironmentObject var updateChecker: UpdateChecker
#endif
    @EnvironmentObject var appPreference: AppPreference
    
    @AppStorage("DisableCloudSync") var isICloudDisabled: Bool = false
    
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup
    
    @State private var isDisclosureGroupUnspportedAlertPresented = false
    struct DisclosureGroupUnspportedError: LocalizedError {
        var errorDescription: String? {
            "Disclosure Group Style is unavailable below macOS 13.0."
        }
    }

    private var usesCompactLayout: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    var body: some View {
        SettingsFormContainer {
            content()
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        Section {
            appearanceSettingCell(.localizable(.settingsAppAppearanceName), selection: $appPreference.appearance)
            appearanceSettingCell(.localizable(.settingsExcalidrawAppearanceName), selection: $appPreference.excalidrawAppearance)
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsAppAppearanceName))
            } else {
                Text(.localizable(.settingsAppAppearanceName))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

#if os(macOS)
        Section {
            KeyboardShortcuts.Recorder(for: .toggleScreenAnnotation) {
                Text(localizable: .screenAnnotationTitle)
            }
            .shortcutValidation { shortcut in
                MainActor.assumeIsolated {
                    Self.validateScreenAnnotationShortcut(shortcut)
                }
            }
            // The Tools menu mirrors this same shortcut. The package's
            // built-in validator can mistake that mirror for another command.
            .keyboardShortcutsConflictPolicy(
                .init(menuItem: .allow)
            )
            .onAppear {
                Self.resignInitialShortcutRecorderFocus()
            }
        } header: {
            Text(localizable: .settingsKeyboardShortcutsTitle)
        }
#endif
        
        // Folder structure UI
        Section {
            folderStructureStyleSettingCell()
        } footer: {
            folderStructurePreviewFooter()
        }
        
#if DEBUG
        Section {
            let containerShape = RoundedRectangle(cornerRadius: 8)
            HStack(alignment: .top, spacing: 20) {
                Text("Sidebar").font(.headline).foregroundStyle(.secondary)
                Spacer()
                RadioGroup(selected: $appPreference.sidebarLayout) { option, isOn in
                    Image(option.imageName("Sidebar"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(containerShape)
                        .padding(2)
                        .overlay {
                            if isOn.wrappedValue {
                                containerShape.stroke(Color.accentColor.opacity(0.5), lineWidth: 4)
                            }
                        }
                        .onTapGesture {
                            isOn.wrappedValue = true
                        }
                }
            }
            
            HStack(alignment: .top, spacing: 20) {
                Text("Inspector").font(.headline).foregroundStyle(.secondary)
                Spacer()
                RadioGroup(selected: $appPreference.inspectorLayout) { option, isOn in
                    Image(option.imageName("Inspector"))
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(containerShape)
                        .padding(2)
                        .overlay {
                            if isOn.wrappedValue {
                                containerShape.stroke(Color.accentColor.opacity(0.5), lineWidth: 4)
                            }
                        }
                        .onTapGesture {
                            isOn.wrappedValue = true
                        }
                }
            }
        } header: {
            Text("Layout")
        }

#endif

        if FeatureDiscoveryTips.isAvailable {
            Section {
                Button {
                    resetFeatureTips()
                } label: {
                    Label(.localizable(.featureTipsResetButton), systemImage: "lightbulb")
                }
            } header: {
                Text(.localizable(.generalHelpTitle))
            }
        }
        
#if os(macOS) && !APP_STORE
        Section {
            Toggle(.localizable(.settingsUpdatesAutoCheckLabel), isOn: $updateChecker.automaticallyChecksForUpdates)
                .disabled(!updateChecker.canCheckForUpdates)
        } header: {
            if #available(macOS 14.0, *) {
                Text(.localizable(.settingsUpdateHeadline))
            } else {
                Text(.localizable(.settingsUpdateHeadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Spacer()
                Button {
                    updateChecker.updater?.checkForUpdates()
                } label: {
                    Text(.localizable(.settingsUpdatesButtonCheck))
                }
            }
        }
#endif // os(macOS) && !APP_STORE
        
        Section {
            Toggle(
                .localizable(.settingsICloudToggleDisable),
                isOn: Binding {
                    FileManager.default.ubiquityIdentityToken == nil ||
                    isICloudDisabled
                } set: { disabled in
                    isICloudDisabled = disabled
                }
            )
            .modifier(ToggleICloudSyncingModifier())
        } header: {
            Text(localizable: .settingsICloudTitle)
        }
        
        Section {} footer: {
            AsyncButton {
                try await PersistenceController.shared.refreshIndices()
            } label: {
                Text(localizable: .settingsButtonRefreshSpotlightIndices)
            }
        }
    }

    @ViewBuilder
    private func appearanceSettingCell(
        _ title: LocalizedStringKey,
        selection: Binding<AppPreference.Appearance>
    ) -> some View {
        if usesCompactLayout {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .fontWeight(.medium)
                appearancePicker(selection: selection)
            }
            .padding(.vertical, 2)
        } else {
            settingCellView(title) {
                HStack(spacing: 16) {
                    RadioGroup(selected: selection) { option, isOn in
                        RadioButton(isOn: isOn) {
                            Text(option.text)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appearancePicker(selection: Binding<AppPreference.Appearance>) -> some View {
        Picker("", selection: selection) {
            Text(AppPreference.Appearance.light.text).tag(AppPreference.Appearance.light)
            Text(AppPreference.Appearance.dark.text).tag(AppPreference.Appearance.dark)
            Text(AppPreference.Appearance.auto.text).tag(AppPreference.Appearance.auto)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func folderStructureStyleSettingCell() -> some View {
        if usesCompactLayout {
            VStack(alignment: .leading, spacing: 10) {
                Text(.localizable(.settingsFolderStructureStyleTitle))
                    .fontWeight(.medium)
                folderStructureStylePicker()
            }
            .padding(.vertical, 2)
        } else {
            HStack {
                Text(.localizable(.settingsFolderStructureStyleTitle))
                Spacer()
                folderStructureStylePicker()
            }
        }
    }

    @ViewBuilder
    private func folderStructureStylePicker() -> some View {
        if usesCompactLayout {
            folderStructureStylePickerContent()
                .frame(maxWidth: .infinity)
        } else {
            folderStructureStylePickerContent()
                .fixedSize()
        }
    }

    private func folderStructureStylePickerContent() -> some View {
        Picker(.localizable(.settingsFolderStructureStyleTitle), selection: $folderStructStyle) {
            Text(.localizable(.settingsFolderStructureStyleDisclosureGroup)).tag(FolderStructureStyle.disclosureGroup)
            Text(.localizable(.settingsFolderStructureStyleTreeStructure)).tag(FolderStructureStyle.tree)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .watch(value: folderStructStyle) { newValue in
            if #available(macOS 13.0, *) { } else {
                if newValue == .disclosureGroup {
                    isDisclosureGroupUnspportedAlertPresented.toggle()
                    folderStructStyle = .tree
                }
            }
        }
        .alert(
            isPresented: $isDisclosureGroupUnspportedAlertPresented,
            error: DisclosureGroupUnspportedError()
        ) {

        }
    }

    @ViewBuilder
    private func folderStructurePreviewFooter() -> some View {
        ZStack {
            if usesCompactLayout {
                VStack(alignment: .leading, spacing: 12) {
                    compactFolderStructurePreviewCard {
                        disclosureGroupPreview()
                    }
                    compactFolderStructurePreviewCard {
                        treeStructurePreview()
                    }
                }
                .padding(.top, 4)
            } else {
                HStack {
                    disclosureGroupPreview()
                        .frame(maxWidth: 160)

                    Divider()

                    treeStructurePreview()
                        .frame(maxWidth: 160)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    private func compactFolderStructurePreviewCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
    }

    @ViewBuilder
    private func disclosureGroupPreview() -> some View {
        VStack(spacing: 10) {
            Text(.localizable(.settingsFolderStructureDisclosureGroupStyleTitle))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemSymbol: .chevronDown).font(.footnote)
                        Text(.localizable(.generalFolderName))
                    }

                    VStack(spacing: 4) {
                        Text(.localizable(.generalSubfolderName))
                        Text(.localizable(.generalSubfolderName))
                    }
                    .padding(.leading, 24)
                }

                HStack(spacing: 4) {
                    Image(systemSymbol: .chevronDown).font(.footnote).opacity(0)
                    Text(.localizable(.generalFolderName))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func treeStructurePreview() -> some View {
        let children: [FolderChildren] = [FolderChildren(), FolderChildren()]
        let children2: [FolderChildren] = []

        VStack(spacing: 10) {
            Text(.localizable(.settingsFolderStructureTreeStructureStyleTitle))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    TreeStructureView(children: children) {
                        Text(.localizable(.generalFolderName))
                    } childView: { _ in
                        TreeStructureView(children: children2) {
                            Text(.localizable(.generalSubfolderName))
                        } childView: { _ in

                        }
                    }
                }
                TreeStructureView(children: children) {
                    Text(.localizable(.generalFolderName)).padding(.vertical, 4)
                } childView: { _ in

                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    func settingCellView<T: View, V: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder trailing: @escaping () -> T,
        @ViewBuilder content: (() -> V) = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                trailing()
            }
            
            content()
        }
    }

    private func resetFeatureTips() {
        FeatureDiscoveryTips.requestResetOnNextLaunch()
        alertToast(.init(
            displayMode: .hud,
            type: .complete(.green),
            title: String(localizable: .featureTipsResetToastTitle)
        ))
    }
}

#if os(macOS)
private extension GeneralSettingsView {
    static func resignInitialShortcutRecorderFocus() {
        Task { @MainActor in
            await Task.yield()
            guard let window = NSApp.keyWindow else { return }

            let responder = window.firstResponder
            let recorderHasFocus =
                responder is KeyboardShortcuts.RecorderCocoa
                || (responder as? NSTextView)?.delegate
                    is KeyboardShortcuts.RecorderCocoa
            if recorderHasFocus {
                window.makeFirstResponder(nil)
            }
        }
    }

    static func validateScreenAnnotationShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut
    ) -> KeyboardShortcuts.ValidationResult {
        guard let mainMenu = NSApp.mainMenu,
              let conflict = firstConflictingMenuItem(
                for: shortcut,
                in: mainMenu,
                excludingTitle: String(localizable: .screenAnnotationTitle)
              ) else {
            return .allow
        }

        return .disallow(
            reason: "This keyboard shortcut is already used by the “\(conflict.title)” menu item."
        )
    }

    static func firstConflictingMenuItem(
        for shortcut: KeyboardShortcuts.Shortcut,
        in menu: NSMenu,
        excludingTitle: String
    ) -> NSMenuItem? {
        for item in menu.items {
            var keyEquivalent = item.keyEquivalent
            var modifiers = item.keyEquivalentModifierMask

            if shortcut.modifiers.contains(.shift),
               keyEquivalent.lowercased() != keyEquivalent {
                keyEquivalent = keyEquivalent.lowercased()
                modifiers.insert(.shift)
            }

            if shortcut.nsMenuItemKeyEquivalent == keyEquivalent,
               shortcut.modifiers == modifiers,
               item.title != excludingTitle {
                return item
            }

            if let submenu = item.submenu,
               let conflict = firstConflictingMenuItem(
                    for: shortcut,
                    in: submenu,
                    excludingTitle: excludingTitle
               ) {
                return conflict
            }
        }
        return nil
    }
}
#endif

#if DEBUG
#Preview {
    GeneralSettingsView()
        .environmentObject(AppPreference())
#if os(macOS) && !APP_STORE
        .environmentObject(UpdateChecker())
#endif
}


#Preview {
    if #available(macOS 13.0, *) {
        Form {
            
        }
        .formStyle(.grouped)
        .environmentObject(AppPreference())
    }
}
#endif
