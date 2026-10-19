#if os(iOS)
import ChocofordUI
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import ExcalidrawZ

@MainActor
final class PDFInsertSheetLayoutTests: XCTestCase {
    func testSelectedPDFHasReachableActionsInWideArea() async throws {
        try await assertSelectedPDFActions(size: CGSize(width: 1024, height: 768))
    }

    func testSelectedPDFHasReachableActionsInTallArea() async throws {
        try await assertSelectedPDFActions(size: CGSize(width: 768, height: 1024))
    }

    func testNarrowLayoutKeepsActionsAboveScrollingContent() async throws {
        try await assertActionsAboveScrollingContent(
            size: CGSize(width: 320, height: 768), sizeClass: .compact, textSize: .large
        )
    }

    func testAccessibilityLayoutKeepsActionsAboveScrollingContent() async throws {
        try await assertActionsAboveScrollingContent(
            size: CGSize(width: 1024, height: 768), sizeClass: .regular, textSize: .accessibility5
        )
    }

    func testNarrowAccessibilityLayoutKeepsActionsAboveScrollingContent() async throws {
        try await assertActionsAboveScrollingContent(
            size: CGSize(width: 320, height: 768), sizeClass: .compact, textSize: .accessibility5
        )
    }

    func testShortRegularLayoutKeepsTiledSettingsUsable() async throws {
        var importedItemsPerLine: Int?
        let host = try makeHost(
            size: CGSize(width: 1024, height: 320),
            sizeClass: .regular,
            pdfInfo: syntheticPDF(),
            onInsert: { _, _, _, itemsPerLine in
                importedItemsPerLine = itemsPerLine
                throw InsertFailure.expected
            }
        )
        defer { host.close() }

        let tiled = try await host.element("pdfInsert.mode.tiled")
        XCTAssertTrue(tiled.accessibilityActivate())
        let scrollView = try await host.scrollableContent(containing: "pdfInsert.itemsPerLine")
        scrollView.setContentOffset(
            CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height),
            animated: false
        )
        host.layout()
        let itemsPerLine = try await host.element("pdfInsert.itemsPerLine")
        host.assertVisible(itemsPerLine)
        itemsPerLine.accessibilityIncrement()

        let insert = try await host.element("pdfInsert.confirm")
        host.assertVisible(insert)
        host.assertVisible(try await host.element("pdfInsert.cancel"))
        XCTAssertTrue(insert.accessibilityActivate())
        try await host.waitUntil { importedItemsPerLine != nil }
        XCTAssertEqual(importedItemsPerLine, 2)
    }

    func testCancelDismissesPresentedSheetWithoutInserting() async throws {
        var didDismiss = false
        var didInsert = false
        let host = try SheetHost(
            view: PresentedSheet(pdfInfo: syntheticPDF(), onInsert: { _, _, _, _ in
                didInsert = true
            }, onDismiss: { didDismiss = true }),
            size: CGSize(width: 1024, height: 768)
        )
        defer { host.close() }

        let cancel = try await host.element("pdfInsert.cancel")
        XCTAssertTrue(cancel.accessibilityActivate())
        try await host.waitUntil { didDismiss }
        XCTAssertFalse(didInsert)
    }

    func testSuccessfulInsertDismissesPresentedSheet() async throws {
        let pdf = try syntheticPDF()
        var insertedData: Data?
        var didDismiss = false
        let host = try SheetHost(
            view: PresentedSheet(pdfInfo: pdf, onInsert: { data, _, _, _ in
                insertedData = data
            }, onDismiss: { didDismiss = true }),
            size: CGSize(width: 1024, height: 768)
        )
        defer { host.close() }

        let insert = try await host.element("pdfInsert.confirm")
        XCTAssertTrue(insert.accessibilityActivate())
        try await host.waitUntil { didDismiss }
        XCTAssertEqual(insertedData, pdf.pdfData)
    }

    func testInsertIsDisabledWithoutASelectedPDF() async throws {
        let host = try makeHost(size: CGSize(width: 1024, height: 768), sizeClass: .regular, pdfInfo: nil)
        defer { host.close() }

        let insert = try await host.element("pdfInsert.confirm")
        host.assertVisible(insert)
        XCTAssertTrue(insert.accessibilityTraits.contains(.notEnabled))
        host.assertVisible(try await host.element("pdfInsert.cancel"))
    }

    func testFailedInsertKeepsPDFAndEnablesRetryAfterLoading() async throws {
        let pdf = try syntheticPDF()
        var attempts: [Data] = []
        var pendingInsert: CheckedContinuation<Void, Error>?
        let host = try makeHost(
            size: CGSize(width: 320, height: 768),
            sizeClass: .compact,
            pdfInfo: pdf,
            onInsert: { data, _, _, _ in
                attempts.append(data)
                try await withCheckedThrowingContinuation { pendingInsert = $0 }
            }
        )
        defer {
            pendingInsert?.resume(throwing: InsertFailure.expected)
            host.close()
        }

        let insert = try await host.element("pdfInsert.confirm")
        XCTAssertTrue(insert.accessibilityActivate())
        try await host.waitUntil { pendingInsert != nil }
        let loadingInsert = try await host.element("pdfInsert.confirm")
        XCTAssertTrue(loadingInsert.accessibilityTraits.contains(.notEnabled))

        pendingInsert?.resume(throwing: InsertFailure.expected)
        pendingInsert = nil
        try await host.waitUntil {
            host.findElement("pdfInsert.confirm")?.accessibilityTraits.contains(.notEnabled) == false
        }
        host.assertVisible(try await host.element("pdfInsert.error"))

        let retry = try await host.element("pdfInsert.confirm")
        XCTAssertTrue(retry.accessibilityActivate())
        try await host.waitUntil { attempts.count == 2 && pendingInsert != nil }
        pendingInsert?.resume(throwing: InsertFailure.expected)
        pendingInsert = nil
        try await host.waitUntil {
            host.findElement("pdfInsert.confirm")?.accessibilityTraits.contains(.notEnabled) == false
        }
        XCTAssertEqual(attempts, [pdf.pdfData, pdf.pdfData])
    }

    private func assertSelectedPDFActions(size: CGSize) async throws {
        let pdf = try syntheticPDF()
        var insertedData: Data?
        let host = try makeHost(size: size, sizeClass: .regular, pdfInfo: pdf) { data, _, _, _ in
            insertedData = data
            throw InsertFailure.expected
        }
        defer { host.close() }

        let insert = try await host.element("pdfInsert.confirm")
        host.assertVisible(insert)
        XCTAssertFalse(insert.accessibilityTraits.contains(.notEnabled))
        host.assertVisible(try await host.element("pdfInsert.cancel"))
        XCTAssertTrue(insert.accessibilityActivate())
        try await host.waitUntil { insertedData != nil }
        XCTAssertEqual(insertedData, pdf.pdfData)
    }

    private func assertActionsAboveScrollingContent(
        size: CGSize,
        sizeClass: UserInterfaceSizeClass,
        textSize: DynamicTypeSize
    ) async throws {
        let pdf = try syntheticPDF()
        var insertedData: Data?
        let host = try makeHost(size: size, sizeClass: sizeClass, textSize: textSize, pdfInfo: pdf) { data, _, _, _ in
            insertedData = data
            throw InsertFailure.expected
        }
        defer { host.close() }
        let insert = try await host.element("pdfInsert.confirm")
        let initialFrame = insert.accessibilityFrame
        let scrollView = try await host.scrollableContent()

        scrollView.setContentOffset(
            CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height),
            animated: false
        )
        host.layout()

        let scrolledInsert = try await host.element("pdfInsert.confirm")
        host.assertVisible(scrolledInsert)
        XCTAssertEqual(scrolledInsert.accessibilityFrame, initialFrame)
        host.assertVisible(try await host.element("pdfInsert.cancel"))
        XCTAssertTrue(scrolledInsert.accessibilityActivate())
        try await host.waitUntil { insertedData != nil }
        XCTAssertEqual(insertedData, pdf.pdfData)
    }

    private enum InsertFailure: LocalizedError {
        case expected
        var errorDescription: String? { "Synthetic insert failure" }
    }

    private func makeHost(
        size: CGSize,
        sizeClass: UserInterfaceSizeClass,
        textSize: DynamicTypeSize = .large,
        pdfInfo: PDFDropInfo? = nil,
        onInsert: @escaping (Data, PDFInsertMode, String, Int?) async throws -> Void = { _, _, _, _ in }
    ) throws -> SheetHost {
        let sheet = PDFInsertSheet(pdfInfo: pdfInfo, onInsert: onInsert)
            .environment(\.containerHorizontalSizeClass, sizeClass)
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.dynamicTypeSize, textSize)
        return try SheetHost(view: sheet, size: size)
    }

    private func syntheticPDF() throws -> PDFDropInfo {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { context in
            for page in 1...4 {
                context.beginPage()
                ("PDF layout test page \(page)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
            }
        }
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 4)
        return PDFDropInfo(pdfData: data, fileName: "Layout test.pdf", sceneX: 0, sceneY: 0)
    }

    private struct PresentedSheet: View {
        let pdfInfo: PDFDropInfo
        let onInsert: (Data, PDFInsertMode, String, Int?) async throws -> Void
        let onDismiss: () -> Void
        @State private var isPresented = true

        var body: some View {
            Color.clear
                .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                    PDFInsertSheet(pdfInfo: pdfInfo, onInsert: onInsert)
                        .environment(\.containerHorizontalSizeClass, .regular)
                }
        }
    }

    @MainActor
    private final class SheetHost {
        let window: UIWindow
        let controller: UIViewController
        private let previousKeyWindow: UIWindow?

        init(view: some View, size: CGSize) throws {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let availableSize = scene.coordinateSpace.bounds.size
            guard size.width <= availableSize.width, size.height <= availableSize.height else {
                throw XCTSkip("PDF layout case requires an iPad window at least \(Int(size.width)) by \(Int(size.height)) points")
            }
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            let root = UIViewController()
            window.rootViewController = root
            window.makeKeyAndVisible()
            controller = UIHostingController(rootView: view)
            root.addChild(controller)
            root.view.addSubview(controller.view)
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.didMove(toParent: root)
            layout()
        }

        func layout() {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        func element(_ identifier: String) async throws -> NSObject {
            try await waitUntil { self.findElement(identifier) != nil }
            return try XCTUnwrap(findElement(identifier))
        }

        func findElement(_ identifier: String) -> NSObject? {
            accessibilityObjects().first {
                ($0 as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier
            }
        }

        func assertVisible(_ element: NSObject, file: StaticString = #filePath, line: UInt = #line) {
            let frame = element.accessibilityFrame
            let bounds = window.convert(controller.view.bounds, from: controller.view)
            let screenBounds = window.convert(bounds, to: window.screen.coordinateSpace)
            XCTAssertFalse(frame.isEmpty, file: file, line: line)
            XCTAssertTrue(screenBounds.contains(frame), "Action must fit in the available area", file: file, line: line)
        }

        func scrollableContent(containing identifier: String? = nil) async throws -> UIScrollView {
            var result: UIScrollView?
            try await waitUntil {
                result = self.accessibilityObjects().compactMap { $0 as? UIScrollView }.first {
                    guard $0.contentSize.height > $0.bounds.height, $0.bounds.height > 0 else { return false }
                    guard let identifier else { return true }
                    return self.accessibilityObjects(root: $0).contains {
                        ($0 as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier
                    }
                }
                return result != nil
            }
            return try XCTUnwrap(result)
        }

        func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(3)
            while !condition(), Date() < deadline {
                layout()
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(condition(), "Rendered sheet did not reach the expected state")
        }

        private func accessibilityObjects(root: NSObject? = nil) -> [NSObject] {
            var pending: [NSObject] = [root ?? window]
            var visited: Set<ObjectIdentifier> = []
            var result: [NSObject] = []
            while let object = pending.popLast() {
                guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
                result.append(object)
                if let view = object as? UIView {
                    pending.append(contentsOf: view.subviews)
                }
                let count = object.accessibilityElementCount()
                if count > 0 && count < 10_000 {
                    for index in 0..<count {
                        if let element = object.accessibilityElement(at: index) as? NSObject {
                            pending.append(element)
                        }
                    }
                }
            }
            return result
        }
    }
}
#endif
