//
//  FileHomeSheetPresentation.swift
//  ExcalidrawZ
//

import SwiftUI
import SwiftyAlert

/// One sheet attachment per file home, rather than two on every card.
@MainActor
final class FileHomeSheetPresentation: ObservableObject {
    struct Request: Identifiable {
        enum Content {
            case rename(name: String, onConfirm: (String) -> Void)
            case recovery(file: FileState.ActiveFile, checkpoints: [FileCheckpoint])
        }

        let id = UUID()
        let content: Content
    }

    @Published private(set) var request: Request?
    private var pendingRequests: [Request] = []
    private var isActive = false
    private var isDismissing = false

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        pendingRequests.removeAll()
        request = nil
        isDismissing = false
    }

    func presentRename(name: String, onConfirm: @escaping (String) -> Void) {
        present(Request(content: .rename(name: name, onConfirm: onConfirm)))
    }

    func presentRecovery(file: FileState.ActiveFile, checkpoints: [FileCheckpoint]) {
        present(Request(content: .recovery(file: file, checkpoints: checkpoints)))
    }

    private func present(_ newRequest: Request) {
        // A recovery task can finish after its file home has disappeared.
        guard isActive else { return }
        if request == nil && !isDismissing {
            request = newRequest
        } else {
            pendingRequests.append(newRequest)
        }
    }

    func dismissCurrent() {
        guard request != nil else { return }
        isDismissing = true
        request = nil
    }

    func didDismiss() {
        isDismissing = false
        guard isActive, request == nil, !pendingRequests.isEmpty else { return }
        request = pendingRequests.removeFirst()
    }
}

private struct FileHomeSheetPresentationKey: EnvironmentKey {
    static let defaultValue: FileHomeSheetPresentation? = nil
}

extension EnvironmentValues {
    var fileHomeSheetPresentation: FileHomeSheetPresentation? {
        get { self[FileHomeSheetPresentationKey.self] }
        set { self[FileHomeSheetPresentationKey.self] = newValue }
    }
}

@MainActor
struct FileHomeSheetPresentationModifier: ViewModifier {
    // Own the reference without subscribing the scrolling subtree to sheet changes.
    // Only the small host below observes objectWillChange.
    @State private var presentation = FileHomeSheetPresentation()

    func body(content: Content) -> some View {
        content
            .environment(\.fileHomeSheetPresentation, presentation)
            .background {
                FileHomeSheetPresentationHost(presentation: presentation)
            }
            .onAppear { presentation.activate() }
            .onDisappear { presentation.deactivate() }
    }
}

private struct FileHomeSheetPresentationHost: View {
    @ObservedObject var presentation: FileHomeSheetPresentation

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(
                item: Binding(
                    get: { presentation.request },
                    set: { if $0 == nil { presentation.dismissCurrent() } }
                ),
                onDismiss: { presentation.didDismiss() }
            ) { request in
                switch request.content {
                    case .rename(let name, let onConfirm):
                        RenameSheetContent(text: name, onConfirm: onConfirm)
                    case .recovery(let file, let checkpoints):
                        CheckpointRecoverySheet(file: file, checkpoints: checkpoints)
                            .swiftyAlert()
                }
            }
    }
}
