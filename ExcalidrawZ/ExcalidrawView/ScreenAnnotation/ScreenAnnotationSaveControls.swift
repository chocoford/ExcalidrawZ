#if os(macOS)
import ChocofordUI
import SwiftUI

struct ScreenAnnotationSaveControls: View {
    @ObservedObject var configuration: ScreenAnnotationSaveConfiguration
    @Binding var isFilePickerPresented: Bool
    @Binding var captureScope: ScreenAnnotationCaptureScope

    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void

    var body: some View {
        destinationMenu

        Button(action: onSave) {
            if isSaving {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Save")
                }
            } else {
                Text("Save")
            }
        }
        .help("Save annotation")
        .disabled(isSaving || !canSave)
        .modernButtonStyle(
            style: .glassProminent,
            size: .large,
            shape: .capsule
        )
    }

    private var destinationMenu: some View {
        Menu {
            Picker("Capture Range", selection: $captureScope) {
                Label("Full Screen", systemImage: "macwindow")
                    .tag(ScreenAnnotationCaptureScope.fullScreen)
                Label("Area", systemImage: "viewfinder")
                    .tag(ScreenAnnotationCaptureScope.area)
            }
            .pickerStyle(.inline)

            Section("Save To") {
                Menu {
                    Picker(
                        "Excalidraw File",
                        selection: fileDestinationBinding
                    ) {
                        Label("New File", systemImage: "doc.badge.plus")
                            .tag(Optional(ScreenAnnotationSaveDestination.newFile))

                        if configuration.fileDestination != .newFile {
                            Label(
                                configuration.fileDestination.title,
                                systemImage: "doc.richtext"
                            )
                            .tag(Optional(configuration.fileDestination))
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button {
                        isFilePickerPresented = true
                    } label: {
                        Label("Choose File...", systemImage: "folder")
                    }
                } label: {
                    destinationLabel(
                        title: "Excalidraw File",
                        systemImage: "doc.richtext",
                        isSelected: configuration.destination.isExcalidrawFile
                    )
                }

                Button {
                    configuration.selectDestination(.clipboard)
                } label: {
                    destinationLabel(
                        title: "Clipboard",
                        systemImage: "clipboard",
                        isSelected: configuration.destination == .clipboard
                    )
                }

                Button {
                    configuration.selectDestination(.downloads)
                } label: {
                    destinationLabel(
                        title: "Downloads",
                        systemImage: "arrow.down.circle",
                        isSelected: configuration.destination == .downloads
                    )
                }

                Button {
                    configuration.selectDestination(.customLocation)
                } label: {
                    destinationLabel(
                        title: "Custom Location",
                        systemImage: "folder",
                        isSelected: configuration.destination == .customLocation
                    )
                }
            }

            Picker("Format", selection: $configuration.format) {
                ForEach(configuration.availableFormats, id: \.self) {
                    Text($0.title)
                        .tag($0)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "ellipsis")
        }
        .help("Save destination: \(configuration.title)")
        .buttonStyle(.borderless)
    }

    private var fileDestinationBinding: Binding<ScreenAnnotationSaveDestination?> {
        Binding {
            configuration.destination.isExcalidrawFile
                ? configuration.destination
                : nil
        } set: {
            guard let destination = $0 else { return }
            configuration.selectFileDestination(destination)
        }
    }

    private func destinationLabel(
        title: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}
#endif
