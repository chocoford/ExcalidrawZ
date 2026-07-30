//
//  AdjustElementsTool+FrameOperation.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/30.
//

import Foundation

extension AdjustElementsMiddleware {
    func applyCreateFrameOp(
        _ op: CreateFrameOp,
        elements: [ExcalidrawElement],
        canvasActions: inout [CanvasAction]
    ) throws {
        let targetIDs = try validatedFrameTargetIDs(op.targetIds, elements: elements)
        let padding = op.padding ?? 16
        guard padding.isFinite, padding >= 0 else {
            throw AdjustmentError(message: "createFrame.padding must be a finite number greater than or equal to zero.")
        }

        let name = op.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        canvasActions.append(.createFrame(CreateFrameOp(
            op: op.op,
            targetIds: targetIDs,
            name: name?.isEmpty == false ? name : nil,
            padding: padding,
            captureUpdate: op.captureUpdate ?? .immediately
        )))
    }

    func applySetFrameOp(
        _ op: SetFrameOp,
        elements: [ExcalidrawElement],
        canvasActions: inout [CanvasAction]
    ) throws {
        let targetIDs = try validatedFrameTargetIDs(op.targetIds, elements: elements)
        let frameID: String?

        switch op.frameId {
            case .null:
                frameID = nil
            case .value(let rawFrameID):
                let trimmedFrameID = rawFrameID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedFrameID.isEmpty else {
                    throw AdjustmentError(message: "setFrame.frameId must be a non-empty frame id or null.")
                }
                guard !targetIDs.contains(trimmedFrameID) else {
                    throw AdjustmentError(message: "setFrame cannot add a frame to itself.")
                }
                guard let frame = elements.first(where: { $0.id == trimmedFrameID }),
                      !frame.isDeleted else {
                    throw AdjustmentError(message: "setFrame.frameId \(trimmedFrameID) was not found or is deleted.")
                }
                guard case .frameLike(let frameElement) = frame,
                      frameElement.type == .frame else {
                    throw AdjustmentError(message: "setFrame.frameId \(trimmedFrameID) must reference an ordinary frame.")
                }
                frameID = trimmedFrameID
        }

        canvasActions.append(.setFrame(SetFrameOp(
            op: op.op,
            targetIds: targetIDs,
            frameId: Nullable(frameID),
            captureUpdate: op.captureUpdate ?? .immediately
        )))
    }

    private func validatedFrameTargetIDs(
        _ rawTargetIDs: [String],
        elements: [ExcalidrawElement]
    ) throws -> [String] {
        let targetIDs = uniqueIDs(
            rawTargetIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        guard !targetIDs.isEmpty, !targetIDs.contains(where: \.isEmpty) else {
            throw AdjustmentError(message: "Frame operations require at least one non-empty targetId.")
        }

        for targetID in targetIDs {
            guard let element = elements.first(where: { $0.id == targetID }),
                  !element.isDeleted else {
                throw AdjustmentError(message: "Frame target \(targetID) was not found or is deleted.")
            }
            if case .frameLike = element {
                throw AdjustmentError(message: "Frame target \(targetID) cannot itself be a frame.")
            }
        }
        return targetIDs
    }
}
