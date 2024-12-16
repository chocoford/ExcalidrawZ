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
        print(#function, interaction, tap)
        
        if self.parent?.toolState.inPenMode == false {
            Task {
                try? await self.togglePenMode(enabled: true)
                try? await self.toggleToolbarAction(key: 0)
                self.parent?.toolState.inPenMode = true
            }
        }
        
        let activeTool = self.parent?.toolState.activatedTool
        Task {
            if activeTool == .cursor {
                try? await self.toggleToolbarAction(key: 0)
            } else {
                try? await self.toggleToolbarAction(key: 1)
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
