//
//  AIChatAvailability.swift
//  ExcalidrawZ
//
//  Build-flavor gates for AI chat surfaces.
//

enum AIChatAvailability {
    static var isUnavailableInCurrentBuild: Bool {
        #if os(macOS) && !APP_STORE && !DEBUG
        true
        #else
        false
        #endif
    }
}
