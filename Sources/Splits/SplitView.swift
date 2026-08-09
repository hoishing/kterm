import SwiftUI

/// A two-pane split with a draggable divider. Terminology mirrors Ghostty:
/// "left"/"right" also cover top/bottom when `direction == .vertical`.
struct SplitView<L: View, R: View>: View {
    let direction: SplitViewDirection
    @Binding var split: CGFloat
    let dividerColor: Color
    let left: L
    let right: R
    let onEqualize: () -> Void

    private let minSize: CGFloat = 10
    private let splitterVisibleSize: CGFloat = 1
    private let splitterInvisibleSize: CGFloat = 6

    init(
        _ direction: SplitViewDirection,
        _ split: Binding<CGFloat>,
        dividerColor: Color,
        @ViewBuilder left: () -> L,
        @ViewBuilder right: () -> R,
        onEqualize: @escaping () -> Void
    ) {
        self.direction = direction
        self._split = split
        self.dividerColor = dividerColor
        self.left = left()
        self.right = right()
        self.onEqualize = onEqualize
    }

    var body: some View {
        GeometryReader { geo in
            let leftRect = leftRect(for: geo.size)
            let rightRect = rightRect(for: geo.size, leftRect: leftRect)
            let splitterPoint = splitterPoint(for: geo.size, leftRect: leftRect)

            ZStack(alignment: .topLeading) {
                left
                    .frame(width: leftRect.size.width, height: leftRect.size.height)
                    .offset(x: leftRect.origin.x, y: leftRect.origin.y)
                right
                    .frame(width: rightRect.size.width, height: rightRect.size.height)
                    .offset(x: rightRect.origin.x, y: rightRect.origin.y)
                DividerBar(
                    direction: direction,
                    visibleSize: splitterVisibleSize,
                    invisibleSize: splitterInvisibleSize,
                    color: dividerColor
                )
                .position(splitterPoint)
                .gesture(dragGesture(geo.size))
                .onTapGesture(count: 2, perform: onEqualize)
            }
        }
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                switch direction {
                case .horizontal:
                    let new = min(max(minSize, gesture.location.x), size.width - minSize)
                    split = new / size.width
                case .vertical:
                    let new = min(max(minSize, gesture.location.y), size.height - minSize)
                    split = new / size.height
                }
            }
    }

    private func leftRect(for size: CGSize) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            result.size.width = size.width * split - splitterVisibleSize / 2
        case .vertical:
            result.size.height = size.height * split - splitterVisibleSize / 2
        }
        return result
    }

    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            result.origin.x = leftRect.size.width + splitterVisibleSize / 2
            result.size.width -= result.origin.x
        case .vertical:
            result.origin.y = leftRect.size.height + splitterVisibleSize / 2
            result.size.height -= result.origin.y
        }
        return result
    }

    private func splitterPoint(for size: CGSize, leftRect: CGRect) -> CGPoint {
        switch direction {
        case .horizontal:
            return CGPoint(x: leftRect.size.width, y: size.height / 2)
        case .vertical:
            return CGPoint(x: size.width / 2, y: leftRect.size.height)
        }
    }
}

enum SplitViewDirection {
    case horizontal, vertical
}

/// Visible 1pt line plus a wider invisible hit target for dragging.
private struct DividerBar: View {
    let direction: SplitViewDirection
    let visibleSize: CGFloat
    let invisibleSize: CGFloat
    let color: Color

    var body: some View {
        let total = visibleSize + invisibleSize
        ZStack {
            Color.clear
                .frame(
                    width: direction == .horizontal ? total : nil,
                    height: direction == .vertical ? total : nil)
                .contentShape(Rectangle())
            Rectangle()
                .fill(color)
                .frame(
                    width: direction == .horizontal ? visibleSize : nil,
                    height: direction == .vertical ? visibleSize : nil)
        }
        .onHover { hovering in
            if hovering {
                switch direction {
                case .horizontal: NSCursor.resizeLeftRight.push()
                case .vertical: NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
    }
}
