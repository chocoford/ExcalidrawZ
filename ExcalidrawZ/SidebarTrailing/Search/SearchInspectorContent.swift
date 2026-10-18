//
//  SearchInspectorContent.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

/// Inspector content that bridges to Excalidraw's global search.
/// Plan B: each query also paints highlights on the canvas via `highlightOnCanvas: true`.
struct SearchInspectorContent: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @Environment(FileState.self) var fileState
    @Environment(LayoutState.self) var layoutState
    @Environment(AppPreference.self) var appPreference

    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex: Int? = nil
    @State private var searchTask: Task<Void, Never>?
    @State private var caseSensitive: Bool = true

    private let debounceNanoseconds: UInt64 = 200_000_000  // 0.2s

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    private var contentSpacing: CGFloat {
        isCompactIOS ? 16 : 12
    }

    private var navigationSpacing: CGFloat {
        isCompactIOS ? 10 : 6
    }

    private var caseToggleSize: CGSize {
        isCompactIOS ? CGSize(width: 32, height: 24) : CGSize(width: 22, height: 18)
    }

    private var caseToggleCornerRadius: CGFloat {
        isCompactIOS ? 12 : 4
    }

    private var resultRowHorizontalPadding: CGFloat {
        isCompactIOS ? 10 : 8
    }

    private var resultRowVerticalPadding: CGFloat {
        isCompactIOS ? 8 : 6
    }

    private var resultRowCornerRadius: CGFloat {
        isCompactIOS ? 8 : 6
    }

    var body: some View {
#if os(macOS)
        if appPreference.inspectorLayout == .sidebar {
            content()
                .toolbar {
                    InspectorHeaderToolbar(
                        title: String(localizable: .searchButtonTitle),
                        isInspectorPresented: layoutState.isInspectorPresented
                    )
                }
        } else {
            content()
        }
#else
        content()
#endif
    }

    @ViewBuilder
    private func content() -> some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            searchField
            navigationRow
            resultsList
        }
        .inspectorContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .watch(value: query) { newValue in
            scheduleSearch(for: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
            Task { try? await fileState.excalidrawWebCoordinator?.clearCanvasHighlights() }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        InspectorSearchField(
            text: $query,
            prompt: Text(localizable: .canvasSearchFieldPrompt)
        )
        .onSubmit {
            advanceSelection()
        }
    }

    // MARK: - Navigation row

    @ViewBuilder
    private var navigationRow: some View {
        HStack(spacing: navigationSpacing) {
            caseSensitiveToggle

            Spacer()

            Text(navigationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                goToPrevious()
            } label: {
                navigationButtonIcon(.chevronLeft)
            }
            .buttonStyle(.plain)
            .disabled(results.isEmpty)

            Button {
                goToNext()
            } label: {
                navigationButtonIcon(.chevronRight)
            }
            .buttonStyle(.plain)
            .disabled(results.isEmpty)
        }
        .opacity(results.isEmpty && query.isEmpty ? 0 : 1)
        .controlSize(.small)
    }

    @ViewBuilder
    private var caseSensitiveToggle: some View {
        let shape = RoundedRectangle(cornerRadius: caseToggleCornerRadius)

        Button {
            caseSensitive.toggle()
            if !query.isEmpty {
                scheduleSearch(for: query)
            }
        } label: {
            Text("Aa")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: caseToggleSize.width, height: caseToggleSize.height)
                .background(
                    shape
                        .fill(caseSensitive ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    shape
                        .strokeBorder(
                            caseSensitive ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3),
                            lineWidth: 0.5
                        )
                )
                .foregroundStyle(caseSensitive ? Color.primary : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            caseSensitive
            ? String(localizable: .canvasSearchCaseSensitiveOn)
            : String(localizable: .canvasSearchCaseSensitiveOff)
        )
    }

    @ViewBuilder
    private func navigationButtonIcon(_ symbol: SFSymbol) -> some View {
        if isCompactIOS {
            Image(systemSymbol: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        } else {
            Image(systemSymbol: symbol)
                .contentShape(Rectangle())
        }
    }

    private var navigationLabel: String {
        let current: Int = {
            if let selectedIndex { return selectedIndex + 1 }
            return 0
        }()
        return "\(current) / \(results.count)"
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        if query.isEmpty {
            emptyHint(String(localizable: .canvasSearchResultsQueryEmptyHint))
        } else if results.isEmpty {
            emptyHint(String(localizable: .canvasSearchResultsResultsEmptyHint))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result, index: index)
                                .id(result.id)
                        }
                    }
                }
                .watch(value: selectedIndex) { newIndex in
                    guard let newIndex, results.indices.contains(newIndex) else { return }
                    let id = results[newIndex].id
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyHint(_ text: String) -> some View {
        VStack {
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResult, index: Int) -> some View {
        let isSelected = selectedIndex == index
        Button {
            select(index: index)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemSymbol: result.elementType == .frame ? .squareDashed : .character)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)

                Text(attributedPreview(result.preview))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, resultRowHorizontalPadding)
            .padding(.vertical, resultRowVerticalPadding)
            .contentShape(RoundedRectangle(cornerRadius: resultRowCornerRadius))
            .background(
                RoundedRectangle(cornerRadius: resultRowCornerRadius)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: resultRowCornerRadius)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection

    /// Pressing Enter for the first time picks the first result; subsequent presses cycle forward.
    private func advanceSelection() {
        guard !results.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = (current + 1) % results.count
        } else {
            selectedIndex = 0
        }
        focusCurrentSelection()
    }

    private func goToNext() {
        advanceSelection()
    }

    private func goToPrevious() {
        guard !results.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = current == 0 ? results.count - 1 : current - 1
        } else {
            selectedIndex = results.count - 1
        }
        focusCurrentSelection()
    }

    private func select(index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        focusCurrentSelection()
    }

    private func focusCurrentSelection() {
        guard let index = selectedIndex, results.indices.contains(index) else { return }
        let result = results[index]
        Task {
            try? await fileState.excalidrawWebCoordinator?.focusSearchResult(elementId: result.elementId)
        }
    }

    // MARK: - Search

    private func scheduleSearch(for newQuery: String) {
        searchTask?.cancel()

        if newQuery.isEmpty {
            results = []
            selectedIndex = nil
            Task { try? await fileState.excalidrawWebCoordinator?.clearCanvasHighlights() }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            if Task.isCancelled { return }
            await runSearch(newQuery)
        }
    }

    @MainActor
    private func runSearch(_ q: String) async {
        guard let coordinator = fileState.excalidrawWebCoordinator else {
            results = []
            selectedIndex = nil
            return
        }
        let case_ = caseSensitive
        do {
            let fetched = try await coordinator.searchElements(
                query: q,
                highlightOnCanvas: true,
                caseSensitive: case_
            )
            // Bail out if a newer search (different query or case mode) has started.
            guard query == q, caseSensitive == case_ else { return }
            results = fetched
            selectedIndex = nil
        } catch {
            guard query == q, caseSensitive == case_ else { return }
            results = []
            selectedIndex = nil
        }
    }

    // MARK: - Preview rendering

    /// Build an `AttributedString` with the matched substring highlighted.
    /// Concatenates segments instead of indexing — avoids platform-specific offset APIs.
    private func attributedPreview(_ preview: SearchResult.Preview) -> AttributedString {
        let text = preview.text
        let safeStart = max(0, min(preview.matchStart, text.count))
        let safeLength = max(0, min(preview.matchLength, text.count - safeStart))

        let prefix = String(text.prefix(safeStart))
        let match = String(text.dropFirst(safeStart).prefix(safeLength))
        let suffix = String(text.dropFirst(safeStart + safeLength))

        let leading = preview.moreBefore ? "…" : ""
        let trailing = preview.moreAfter ? "…" : ""

        var attr = AttributedString(leading + prefix)

        var matchAttr = AttributedString(match)
        matchAttr.backgroundColor = Color.yellow.opacity(0.4)
        matchAttr.foregroundColor = .primary
        attr.append(matchAttr)

        attr.append(AttributedString(suffix + trailing))
        return attr
    }
}
