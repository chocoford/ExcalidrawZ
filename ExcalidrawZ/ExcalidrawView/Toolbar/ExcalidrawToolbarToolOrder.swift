//
//  ExcalidrawToolbarToolOrder.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/16.
//

import SwiftUI

struct ExcalidrawToolbarToolOrder: Equatable, Hashable {
    static let storageKey = "toolbarToolOrderData"

    static let defaultTools: [ExcalidrawTool] = [
        .cursor,
        .rectangle,
        .diamond,
        .ellipse,
        .arrow,
        .line,
        .freedraw,
        .text,
        .image,
        .eraser,
        .laser,
        .lasso,
        .hand,
        .frame,
        .webEmbed,
        .magicFrame,
    ]

    private static let shortcutLabels = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    ]

    var tools: [ExcalidrawTool]

    init(tools: [ExcalidrawTool] = Self.defaultTools) {
        self.tools = Self.normalized(tools)
    }

    init(storedData: Data) {
        guard !storedData.isEmpty,
              let ids = try? JSONDecoder().decode([String].self, from: storedData) else {
            self.init()
            return
        }
        self.init(tools: ids.compactMap(ExcalidrawTool.init(toolbarOrderID:)))
    }

    var storedData: Data {
        (try? JSONEncoder().encode(tools.map(\.toolbarOrderID))) ?? Data()
    }

    func pickerItems(
        for sizeClass: ExcalidrawToolbarToolSizeClass
    ) -> (primary: [ExcalidrawTool], secondary: [ExcalidrawTool]) {
        guard sizeClass != .expanded else {
            return (tools, [])
        }

        let primaryCount = Self.primaryToolCount(for: sizeClass)
        return (
            Array(tools.prefix(primaryCount)),
            Array(tools.dropFirst(primaryCount))
        )
    }

    func shortcutLabel(for tool: ExcalidrawTool) -> String? {
        guard tool.supportsOrderedNumericShortcut,
              let index = tools.firstIndex(of: tool),
              index < Self.shortcutLabels.count else {
            return nil
        }
        return Self.shortcutLabels[index]
    }

    func tool(forShortcutNumber number: Int) -> ExcalidrawTool? {
        let index = number == 0 ? 9 : number - 1
        guard tools.indices.contains(index) else { return nil }

        let tool = tools[index]
        guard tool.supportsOrderedNumericShortcut else { return nil }
        return tool
    }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        tools.move(fromOffsets: offsets, toOffset: destination)
        tools = Self.normalized(tools)
    }

    private static func primaryToolCount(
        for sizeClass: ExcalidrawToolbarToolSizeClass
    ) -> Int {
        switch sizeClass {
            case .dense, .compact:
                6
            case .regular:
                9
            case .expanded:
                defaultTools.count
        }
    }

    private static func normalized(_ tools: [ExcalidrawTool]) -> [ExcalidrawTool] {
        var seen = Set<ExcalidrawTool>()
        var normalized: [ExcalidrawTool] = []

        for tool in tools where defaultTools.contains(tool) && !seen.contains(tool) {
            normalized.append(tool)
            seen.insert(tool)
        }

        for tool in defaultTools where !seen.contains(tool) {
            normalized.append(tool)
        }

        return normalized
    }
}
