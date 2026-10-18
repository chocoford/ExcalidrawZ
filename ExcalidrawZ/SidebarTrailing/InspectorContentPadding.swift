import SwiftUI
import ChocofordUI

private struct InspectorContentPadding: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    let edges: Edge.Set

    private var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    func body(content: Content) -> some View {
        let horizontal: CGFloat = isCompactIOS ? 20 : 10
        let vertical: CGFloat = isCompactIOS ? 16 : 8

        content.padding(EdgeInsets(
            top: edges.contains(.top) ? vertical : 0,
            leading: edges.contains(.leading) ? horizontal : 0,
            bottom: edges.contains(.bottom) ? vertical : 0,
            trailing: edges.contains(.trailing) ? horizontal : 0
        ))
    }
}

extension View {
    /// Applies the shared outer margins for inspector content.
    func inspectorContentPadding(_ edges: Edge.Set = .all) -> some View {
        modifier(InspectorContentPadding(edges: edges))
    }
}
