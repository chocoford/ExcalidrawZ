//
//  ExcalidrawCore+PencilInteraction.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/16/24.
//


#if os(iOS)
import UIKit

extension ExcalidrawCore: UIPencilInteractionDelegate {
    
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {        
        if self.parent?.toolState.inPenMode == false {
            Task {
                try? await self.parent?.toolState.togglePenMode(enabled: true, pencilConnected: true)
                try? await self.toggleToolbarAction(key: ExcalidrawTool.freedraw.rawValue)
            }
        } else {
            let activeTool = self.parent?.toolState.activatedTool
            let previousActiveTool = self.parent?.toolState.previousActivatedTool
            Task {
                if activeTool == .eraser {
                    if self.parent?.toolState.pencilInteractionMode == .fingerSelect, previousActiveTool == .cursor {
                        try? await self.toggleToolbarAction(key: ExcalidrawTool.freedraw.keyEquivalent!)
                    } else {
                        try? await self.toggleToolbarAction(key: previousActiveTool?.keyEquivalent ?? ExcalidrawTool.freedraw.keyEquivalent!)
                    }
                } else {
                    try? await self.toggleToolbarAction(key: ExcalidrawTool.eraser.keyEquivalent!)
                }
            }
        }
    }
    
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        print(#function, interaction, squeeze)
    }
    
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        if #available(iOS 17.5, *) {
            print(#function, interaction, "#available(iOS 17.5, *)")
        } else {
            print(#function, interaction)
        }
    }
}
#endif
