//
//  ActivityView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/14/24.
//

import SwiftUI

#if os(iOS)
struct PDFFile: Transferable {
    var name: String?
    var makeImage: () async -> UIImage
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            try await SentTransferredFile(exportPDF(image: item.makeImage(), name: item.name))
        }
    }
}

extension View {
    public func activitySheet<T>(item: Binding<T?>) -> some View {
        modifier(ActivitySheetViewModifier(item: item))
    }
}

struct ActivitySheetViewModifier<T>: ViewModifier {
    @Binding var items: [T]
    
    init(items: Binding<[T]>) {
        self._items = items
    }
    init(item: Binding<T?>) {
        self._items = Binding(get: {
            if let item = item.wrappedValue {
                return [item]
            } else {
                return []
            }
        }, set: { val in
            item.wrappedValue = val.first
        })
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(get: {
                    !items.isEmpty
                }, set: { val in
                    if !val {
                        items.removeAll()
                    }
                })
            ) {
                ActivityView(activityItems: items)
                    .presentationDetents([.medium, .large])
            }
    }
}

struct ActivityView<T>: UIViewControllerRepresentable {
    let activityItems: [T]
    let applicationActivities: [UIActivity]?

    init(activityItems: [T], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif


