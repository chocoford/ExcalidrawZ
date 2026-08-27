//
//  ExcalidrawCore+NativeEyeDropper.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/08/17.
//

import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension ExcalidrawCore {
    struct NativeEyeDropperRequest: Codable, Sendable {
        let requestId: String
        let colorPickerType: String?
        let theme: String?
    }

    struct NativeEyeDropperCompletion: Encodable, Sendable {
        let requestId: String
        var color: String?
        var cancelled: Bool?

        static func selected(requestId: String, color: String) -> Self {
            Self(requestId: requestId, color: color, cancelled: nil)
        }

        static func cancelled(requestId: String) -> Self {
            Self(requestId: requestId, color: nil, cancelled: true)
        }
    }

    @MainActor
    func setNativeEyeDropperEnabled(_ enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.setNativeEyeDropperEnabled(enabled);",
            arguments: ["enabled": enabled],
            contentWorld: .page
        )
    }

    @MainActor
    func completeNativeEyeDropper(_ completion: NativeEyeDropperCompletion) async throws {
        let payload = try encodeJSON(completion)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.completeNativeEyeDropper(\(payload));",
            arguments: [:],
            contentWorld: .page
        )
    }
}

final class ExcalidrawNativeEyeDropperCoordinator: NSObject {
    private weak var core: ExcalidrawCore?
    private var activeRequest: ExcalidrawCore.NativeEyeDropperRequest?

#if os(macOS)
    private var colorSampler: NSColorSampler?
#elseif os(iOS)
    private var colorPicker: UIColorPickerViewController?
    private var didSelectColor = false
#endif

    init(core: ExcalidrawCore) {
        self.core = core
        super.init()
    }

    @MainActor
    func request(_ request: ExcalidrawCore.NativeEyeDropperRequest) async {
#if os(iOS)
        if let colorPicker {
            colorPicker.delegate = nil
            colorPicker.dismiss(animated: false)
            self.colorPicker = nil
        }
#endif
        if let activeRequest {
            await complete(.cancelled(requestId: activeRequest.requestId))
        }
        activeRequest = request

#if os(macOS)
        let sampler = NSColorSampler()
        colorSampler = sampler
        let color = await sampler.sample()
        guard activeRequest?.requestId == request.requestId else {
            return
        }
        colorSampler = nil
        guard let color,
              let hex = Self.sRGBHex(color) else {
            await complete(.cancelled(requestId: request.requestId))
            return
        }
        await complete(.selected(requestId: request.requestId, color: hex))
#elseif os(iOS)
        guard let presenter = presentationViewController() else {
            core?.logger.warning("Unable to present native eye dropper without an active view controller")
            await complete(.cancelled(requestId: request.requestId))
            return
        }

        didSelectColor = false
        let picker = UIColorPickerViewController()
        picker.delegate = self
        picker.supportsAlpha = false
        switch request.theme {
            case "dark":
                picker.overrideUserInterfaceStyle = .dark
            case "light":
                picker.overrideUserInterfaceStyle = .light
            default:
                picker.overrideUserInterfaceStyle = .unspecified
        }
        colorPicker = picker
        presenter.present(picker, animated: true)
#endif
    }

    @MainActor
    func invalidate() {
        activeRequest = nil
#if os(macOS)
        colorSampler = nil
#elseif os(iOS)
        colorPicker?.delegate = nil
        colorPicker?.dismiss(animated: false)
        colorPicker = nil
        didSelectColor = false
#endif
    }

    @MainActor
    private func complete(_ completion: ExcalidrawCore.NativeEyeDropperCompletion) async {
        guard activeRequest?.requestId == completion.requestId else { return }
        activeRequest = nil
        do {
            try await core?.completeNativeEyeDropper(completion)
        } catch {
            core?.logger.warning("Failed to complete native eye dropper request \(completion.requestId): \(error)")
        }
    }

#if os(macOS)
    private static func sRGBHex(_ color: NSColor) -> String? {
        guard let color = color.usingColorSpace(.sRGB) else { return nil }
        return hex(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent
        )
    }
#elseif os(iOS)
    @MainActor
    private func presentationViewController() -> UIViewController? {
        let rootViewController = core?.webView.window?.rootViewController
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        return rootViewController?.nativeEyeDropperTopmostViewController
    }

    private static func sRGBHex(_ color: UIColor) -> String? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.cgColor.converted(
                to: colorSpace,
                intent: .defaultIntent,
                options: nil
              ),
              let components = converted.components,
              components.count >= 3 else {
            return nil
        }
        return hex(red: components[0], green: components[1], blue: components[2])
    }
#endif

    private static func hex(red: CGFloat, green: CGFloat, blue: CGFloat) -> String {
        let component: (CGFloat) -> Int = { value in
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X",
            component(red),
            component(green),
            component(blue)
        )
    }
}

#if os(iOS)
extension ExcalidrawNativeEyeDropperCoordinator: UIColorPickerViewControllerDelegate {
    @MainActor
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        guard viewController === colorPicker else { return }
        didSelectColor = true
    }

    @MainActor
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        guard viewController === colorPicker,
              let request = activeRequest else {
            return
        }
        colorPicker = nil
        guard didSelectColor,
              let hex = Self.sRGBHex(viewController.selectedColor) else {
            Task { @MainActor in
                await complete(.cancelled(requestId: request.requestId))
            }
            return
        }
        Task { @MainActor in
            await complete(.selected(requestId: request.requestId, color: hex))
        }
    }
}

private extension UIViewController {
    var nativeEyeDropperTopmostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.nativeEyeDropperTopmostViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.nativeEyeDropperTopmostViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.nativeEyeDropperTopmostViewController
        }
        return self
    }
}
#endif
