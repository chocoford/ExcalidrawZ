//
//  DebugNotifyModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI

#if DEBUG
extension Notification.Name {
    static let debugNotify = Notification.Name("DebugNotify")
}
#endif

extension View {
    @MainActor @ViewBuilder
    public func debugNotify() -> some View {
        modifier(DebugNotifyModifier())
    }
}

struct DebugNotifyModifier: ViewModifier {
#if DEBUG
    @State private var debugNotifications: [String] = []
#endif
    
    func body(content: Content) -> some View {
        content
#if DEBUG
            .overlay {
                if !debugNotifications.isEmpty {
                    VStack {
                        ScrollView {
                            VStack {
                                ForEach(debugNotifications, id: \.self) { n in
                                    Text(n)
                                }
                            }
                        }
                        
                        Button {
                            debugNotifications.removeAll()
                        } label: {
                            Text("Clear")
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugNotify)) { notification in
                if let output = notification.object {
                    debugNotifications.append(String(describing: output))
                }
            }
#endif
    }
}
