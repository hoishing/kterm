import SwiftUI

/// Renders a tab's `SplitTree`, hosting each leaf's persistent `SurfaceView`.
struct SplitTreeView: View {
    let tab: TerminalTab
    let backgroundColor: Color
    let onResize: (SplitTree.Node, Double) -> Void
    let onEqualize: () -> Void

    var body: some View {
        if let node = tab.tree.zoomed ?? tab.tree.root {
            SplitSubtreeView(
                node: node,
                focusedTerminalID: tab.focusedTerminalID,
                backgroundColor: backgroundColor,
                onResize: onResize,
                onEqualize: onEqualize
            )
            // Force SwiftUI to rebuild on structural tree changes rather than
            // relying on implicit identity (Ghostty issue #7546).
            .id(node.structuralIdentity)
        } else {
            backgroundColor
        }
    }
}

private struct SplitSubtreeView: View {
    let node: SplitTree.Node
    let focusedTerminalID: UUID?
    let backgroundColor: Color
    let onResize: (SplitTree.Node, Double) -> Void
    let onEqualize: () -> Void

    var body: some View {
        switch node {
        case .leaf(let terminal):
            SurfaceContainer(
                terminal: terminal,
                wantsFocus: terminal.id == focusedTerminalID
            )
            .overlay { AttentionBorder(active: terminal.showAttention) }

        case .split(let split):
            let direction: SplitViewDirection = split.direction == .horizontal
                ? .horizontal : .vertical
            SplitView(
                direction,
                .init(
                    get: { CGFloat(split.ratio) },
                    set: { onResize(node, Double($0)) }
                ),
                dividerColor: Color(nsColor: .separatorColor),
                left: {
                    SplitSubtreeView(
                        node: split.left,
                        focusedTerminalID: focusedTerminalID,
                        backgroundColor: backgroundColor,
                        onResize: onResize,
                        onEqualize: onEqualize)
                },
                right: {
                    SplitSubtreeView(
                        node: split.right,
                        focusedTerminalID: focusedTerminalID,
                        backgroundColor: backgroundColor,
                        onResize: onResize,
                        onEqualize: onEqualize)
                },
                onEqualize: onEqualize
            )
        }
    }
}
