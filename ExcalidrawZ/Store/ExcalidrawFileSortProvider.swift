//
//  ExcalidrawFileSortProvider.swift
//  ExcalidrawZ
//

import Foundation

enum ExcalidrawFileSortField: String, Hashable {
    case updatedAt
    case name
    case rank
}

/// Defines one ordering policy for every file source. Storage adapters only
/// map their own metadata into `Values`; they must not redefine sort order.
enum ExcalidrawFileSortProvider {
    struct Values {
        let name: String
        let updatedAt: Date?
        let createdAt: Date?
        let rank: Int64?

        init(
            name: String,
            updatedAt: Date?,
            createdAt: Date?,
            rank: Int64? = nil
        ) {
            self.name = name
            self.updatedAt = updatedAt
            self.createdAt = createdAt
            self.rank = rank
        }
    }

    static func sorted<Element>(
        _ elements: [Element],
        by field: ExcalidrawFileSortField,
        values: (Element) -> Values
    ) -> [Element] {
        elements
            .map { (element: $0, values: values($0)) }
            .sorted { lhs, rhs in
                compare(lhs.values, before: rhs.values, by: field)
            }
            .map { $0.element }
    }

    static func fileSortDescriptors(
        for field: ExcalidrawFileSortField
    ) -> [SortDescriptor<File>] {
        switch field {
        case .updatedAt:
            return [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.name, order: .forward),
            ]
        case .name:
            return [
                SortDescriptor(\.name, order: .forward),
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        case .rank:
            return [
                SortDescriptor(\.rank, order: .forward),
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.name, order: .forward),
            ]
        }
    }

    static func collaborationFileSortDescriptors(
        for field: ExcalidrawFileSortField,
        prioritizesVisitedAt: Bool = false
    ) -> [SortDescriptor<CollaborationFile>] {
        switch field {
        case .updatedAt:
            let dateDescriptors: [SortDescriptor<CollaborationFile>] = [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.name, order: .forward),
            ]
            if prioritizesVisitedAt {
                return [SortDescriptor(\.visitedAt, order: .reverse)]
                    + dateDescriptors
            }
            return dateDescriptors
        case .name:
            return [
                SortDescriptor(\.name, order: .forward),
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
            ]
        case .rank:
            return [
                SortDescriptor(\.rank, order: .forward),
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.name, order: .forward),
            ]
        }
    }

    private static func compare(
        _ lhs: Values,
        before rhs: Values,
        by field: ExcalidrawFileSortField
    ) -> Bool {
        switch field {
        case .name:
            let nameComparison = compareNames(lhs.name, rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return compareDates(lhs, before: rhs)
        case .rank:
            if let lhsRank = lhs.rank,
               let rhsRank = rhs.rank,
               lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return compareDates(lhs, before: rhs)
        case .updatedAt:
            return compareDates(lhs, before: rhs)
        }
    }

    private static func compareDates(_ lhs: Values, before rhs: Values) -> Bool {
        let lhsUpdatedAt = lhs.updatedAt ?? .distantPast
        let rhsUpdatedAt = rhs.updatedAt ?? .distantPast
        if lhsUpdatedAt != rhsUpdatedAt {
            return lhsUpdatedAt > rhsUpdatedAt
        }

        let lhsCreatedAt = lhs.createdAt ?? .distantPast
        let rhsCreatedAt = rhs.createdAt ?? .distantPast
        if lhsCreatedAt != rhsCreatedAt {
            return lhsCreatedAt > rhsCreatedAt
        }
        return compareNames(lhs.name, rhs.name) == .orderedAscending
    }

    private static func compareNames(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedCaseInsensitiveCompare(rhs)
    }
}
