import Foundation

/// Keeps delayed focus events and completed purchases scoped to the panel that started them.
struct PaywallPanelSession {
    private(set) var id: UUID?
    private var protectedInteractionCount = 0

    var hasProtectedInteractions: Bool { protectedInteractionCount > 0 }

    mutating func begin() -> UUID {
        let id = UUID()
        self.id = id
        protectedInteractionCount = 0
        return id
    }

    @discardableResult
    mutating func end(_ id: UUID) -> Bool {
        guard self.id == id else { return false }
        self.id = nil
        protectedInteractionCount = 0
        return true
    }

    mutating func updateProtection(_ isBeginning: Bool, for id: UUID) {
        guard self.id == id else { return }
        protectedInteractionCount = max(0, protectedInteractionCount + (isBeginning ? 1 : -1))
    }

    func shouldDismiss(
        isApplicationActive: Bool,
        keyWindowBelongsToPanel: Bool,
        hasAttachedSheet: Bool
    ) -> Bool {
        id != nil && !hasProtectedInteractions && !hasAttachedSheet &&
        (!isApplicationActive || !keyWindowBelongsToPanel)
    }
}
