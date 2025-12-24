//
//  SensoryFeedbackButton.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/21/25.
//

import SwiftUI
import ChocofordUI

struct SensoryFeedbackButton: View {
    var action: () async throws -> Void
    var label: AnyView
    
    
    init<Label: View>(
        action: @escaping () async throws -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = AnyView(label())
    }
    
    @State private var sensorySuccessFeedbackFlag = false
    @State private var sensoryErrorFeedbackFlag = false
    
    var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            AsyncButton {
                do {
                    try await action()
                    sensorySuccessFeedbackFlag.toggle()
                } catch {
                    sensoryErrorFeedbackFlag.toggle()
                    throw error
                }
            } label: {
                label
            }
            .sensoryFeedback(.success, trigger: sensorySuccessFeedbackFlag)
            .sensoryFeedback(.error, trigger: sensoryErrorFeedbackFlag)
        } else {
            AsyncButton {
                try await action()
            } label: {
                label
            }
        }

        
    }
}
