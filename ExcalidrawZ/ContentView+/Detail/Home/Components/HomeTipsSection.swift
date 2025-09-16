//
//  HomeTipsSection.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/29/25.
//

import SwiftUI
import SFSafeSymbols

struct HomeTipsSection: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemSymbol: .lightbulb)
                Text(.localizable(.homeTipsTitle))
                Spacer()
            }
            .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    HomeTipItemView.whatsNew
                    HomeTipItemView.orginzeFiles
                    HomeTipItemView.fileHistory
                    HomeTipItemView.share
                    HomeTipItemView.library
                }
            }
            .scrollClipDisabledIfAvailable()
        }
    }
}


struct HomeTipItemView: View {
    
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var image: AnyView
    var detail: AnyView
    var action: (() -> Void)?
    
    init<Detail: View>(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        image: Image,
        @ViewBuilder detail: () -> Detail
    ) {
        self.title = title
        self.message = message
        self.image = AnyView(
            image
                .resizable()
        )
        self.detail = AnyView(detail())
    }
    
    init<Detail: View>(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        icon: SFSymbol,
        @ViewBuilder detail: () -> Detail
    ) {
        self.title = title
        self.message = message
        self.image = AnyView(
            Image(systemSymbol: icon)
                .resizable()
                .padding(8)
        )
        self.detail = AnyView(detail())
    }
    
//    init(
//        title: LocalizedStringKey,
//        message: LocalizedStringKey,
//        image: Image,
//        action: @escaping () -> Void
//    ) {
//        self.title = title
//        self.message = message
//        self.image = image
//        self.detail = AnyView(EmptyView())
//        self.action = action
//    }
    
    @State private var isDetailPresented = false
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .gray.opacity(0.2), radius: isHovered ? 4 : 0)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator)
                
                image
                    .scaledToFit()
                    .padding(20)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 100)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title2).fontWeight(.semibold)
                Text(message).font(.body).foregroundStyle(.secondary)
            }
        }
        .frame(width: 230)
        .padding(4)
        .contentShape(Rectangle())
        .onHover { isHovered in
            withAnimation {
                self.isHovered = isHovered
            }
        }
        .onTapGesture {
            if let action {
                action()
            } else {
                isDetailPresented.toggle()
            }
        }
        .sheet(isPresented: $isDetailPresented) {
            detail
        }
    }
}

struct TipDetailContainer: View {
    @Environment(\.dismiss) private var dismiss
    
    var spacing: CGFloat
    var content: AnyView
    
    init<Content: View>(
        spacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = AnyView(content())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 120)
            .frame(width: 900)
        }
        // .scrollIndicators(.hidden)
        .frame(maxHeight: 700)
        .overlay(alignment: .topLeading) {
            ZStack {
                if #available(macOS 26.0, *) {
                    dismissButton()
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glass)
                        .controlSize(.extraLarge)
                } else {
                    dismissButton()
                        .buttonStyle(.borderless)
                        .controlSize(.large)
                }
            }
            .padding(28)
        }
    }
    
    
    @MainActor @ViewBuilder
    private func dismissButton() -> some View {
        Button {
            dismiss()
        } label: {
            Image(systemSymbol: .xmark)
        }
        .keyboardShortcut("w", modifiers: .command)
    }
}



#Preview {
    HomeTipsSection()
        .padding()
}
