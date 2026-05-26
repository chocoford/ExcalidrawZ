//
//  ChatScrollRowModel.swift
//  ExcalidrawZ
//

import Foundation

struct ChatScrollRowModel: Identifiable {
    enum Kind {
        case hiddenHistory(hiddenGroupCount: Int, isLoading: Bool)
        case group(MessageGroup)
        case assistantLoadingSlot(isVisible: Bool)
        case assistantItem(AssistantRoundTableItem)
        case assistantAction(AssistantRoundTableAction)
        case transientError(id: UUID, message: String)
    }

    let id: String
    let kind: Kind
}

struct ChatAssistantLoadingSlot {
    let id: String
    let isVisible: Bool
}

struct NativeChatRowSnapshot: Identifiable {
    let model: ChatScrollRowModel
    let renderKey: String

    var id: String { model.id }
}

struct ChatMessageWindowState {
    var pageSize: Int = 20
    var scopeID: String?
    var oldestLoadedGroupID: String?
    var isLoadingMore: Bool = false

    func visibleGroups(
        from groups: [MessageGroup],
        scopeID currentScopeID: String?
    ) -> [MessageGroup] {
        guard !groups.isEmpty else { return [] }
        let startIndex = loadedStartIndex(in: groups, scopeID: currentScopeID)
        return Array(groups[startIndex...])
    }

    func hiddenGroupCount(
        in groups: [MessageGroup],
        scopeID currentScopeID: String?
    ) -> Int {
        guard !groups.isEmpty else { return 0 }
        return loadedStartIndex(in: groups, scopeID: currentScopeID)
    }

    mutating func reset(scopeID newScopeID: String?) {
        scopeID = newScopeID
        oldestLoadedGroupID = nil
        isLoadingMore = false
    }

    mutating func reconcile(
        groups: [MessageGroup],
        scopeID currentScopeID: String?
    ) {
        if scopeID != currentScopeID {
            reset(scopeID: currentScopeID)
        }

        guard !groups.isEmpty else {
            oldestLoadedGroupID = nil
            return
        }

        if let oldestLoadedGroupID,
           groups.contains(where: { $0.id == oldestLoadedGroupID }) {
            return
        }

        let startIndex = max(0, groups.count - pageSize)
        oldestLoadedGroupID = groups[startIndex].id
    }

    mutating func loadMore(
        groups: [MessageGroup],
        scopeID currentScopeID: String?
    ) {
        reconcile(groups: groups, scopeID: currentScopeID)
        guard !groups.isEmpty else { return }
        let currentStartIndex = loadedStartIndex(in: groups, scopeID: currentScopeID)
        guard currentStartIndex > 0 else { return }
        let nextStartIndex = max(0, currentStartIndex - pageSize)
        oldestLoadedGroupID = groups[nextStartIndex].id
    }

    private func loadedStartIndex(
        in groups: [MessageGroup],
        scopeID currentScopeID: String?
    ) -> Int {
        guard !groups.isEmpty else { return 0 }
        if scopeID == currentScopeID,
           let oldestLoadedGroupID,
           let index = groups.firstIndex(where: { $0.id == oldestLoadedGroupID }) {
            return index
        }
        return max(0, groups.count - pageSize)
    }
}

enum NativeChatRowDiff {
    case same(changedIndexes: IndexSet)
    case append(changedIndexes: IndexSet, insertedRange: Range<Int>)
    case replaceSuffix(
        commonPrefixCount: Int,
        changedIndexes: IndexSet,
        oldSuffixRange: Range<Int>,
        newSuffixRange: Range<Int>
    )
    case reload

    static func make(
        previous: [NativeChatRowSnapshot],
        next: [NativeChatRowSnapshot]
    ) -> NativeChatRowDiff {
        let previousIDs = previous.map(\.id)
        let nextIDs = next.map(\.id)

        if previousIDs == nextIDs {
            return .same(
                changedIndexes: changedIndexes(
                    previous: previous,
                    next: next,
                    in: 0..<next.count
                )
            )
        }

        if previousIDs.elementsEqual(nextIDs.prefix(previousIDs.count)) {
            return .append(
                changedIndexes: changedIndexes(
                    previous: previous,
                    next: next,
                    in: 0..<previous.count
                ),
                insertedRange: previous.count..<next.count
            )
        }

        let commonPrefixCount = zip(previousIDs, nextIDs)
            .prefix { pair in pair.0 == pair.1 }
            .count

        guard commonPrefixCount > 0 else {
            return .reload
        }

        return .replaceSuffix(
            commonPrefixCount: commonPrefixCount,
            changedIndexes: changedIndexes(
                previous: previous,
                next: next,
                in: 0..<commonPrefixCount
            ),
            oldSuffixRange: commonPrefixCount..<previous.count,
            newSuffixRange: commonPrefixCount..<next.count
        )
    }

    private static func changedIndexes(
        previous: [NativeChatRowSnapshot],
        next: [NativeChatRowSnapshot],
        in range: Range<Int>
    ) -> IndexSet {
        var result = IndexSet()
        for index in range
            where previous.indices.contains(index)
            && next.indices.contains(index)
            && previous[index].renderKey != next[index].renderKey {
            result.insert(index)
        }
        return result
    }
}
