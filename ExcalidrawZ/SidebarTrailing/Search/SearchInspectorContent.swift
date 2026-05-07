//
//  SearchInspectorContent.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/2/26.
//

import SwiftUI

import ChocofordUI

/// Inspector content that bridges to Excalidraw's global search.
/// Plan B: each query also paints highlights on the canvas via `highlightOnCanvas: true`.
struct SearchInspectorContent: View {
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var appPreference: AppPreference

    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex: Int? = nil
    @State private var searchTask: Task<Void, Never>?
    @State private var caseSensitive: Bool = true

    private let debounceNanoseconds: UInt64 = 200_000_000  // 0.2s

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
        VStack(alignment: .leading, spacing: 12) {
            searchField
            navigationRow
            resultsList
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: query) { newValue in
            scheduleSearch(for: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
            Task { try? await fileState.excalidrawWebCoordinator?.clearCanvasHighlights() }
        }
    }

    // MARK: - Search field

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text(localizable: .canvasSearchFieldPrompt))
                .textFieldStyle(.plain)
                .onSubmit {
                    advanceSelection()
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.regularMaterial)
        }
    }

    // MARK: - Navigation row

    @ViewBuilder
    private var navigationRow: some View {
        HStack(spacing: 6) {
            caseSensitiveToggle

            Spacer()

            Text(navigationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                goToPrevious()
            } label: {
                Image(systemSymbol: .chevronLeft)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(results.isEmpty)

            Button {
                goToNext()
            } label: {
                Image(systemSymbol: .chevronRight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(results.isEmpty)
        }
        .opacity(results.isEmpty && query.isEmpty ? 0 : 1)
        .controlSize(.small)
    }

    @ViewBuilder
    private var caseSensitiveToggle: some View {
        Button {
            caseSensitive.toggle()
            if !query.isEmpty {
                scheduleSearch(for: query)
            }
        } label: {
            Text("Aa")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(caseSensitive ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
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
                .onChange(of: selectedIndex) { newIndex in
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
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
