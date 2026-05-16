//
//  ChatScrollRowModel.swift
//  ExcalidrawZ
//

import Foundation

struct ChatScrollRowModel: Identifiable {
    enum Kind {
        case hiddenHistory(hiddenGroupCount: Int, isLoading: Bool)
        case group(MessageGroup)
        case assistantItem(AssistantRoundTableItem)
        case assistantAction(AssistantRoundTableAction)
        case transientError(id: UUID, message: String)
    }

    let id: String
    let kind: Kind
}

struct NativeChatRowSnapshot: Identifiable {
    let model: ChatScrollRowModel
    let renderKey: String

    var id: String { model.id }
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
