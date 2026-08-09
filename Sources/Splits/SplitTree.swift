import Foundation
import CoreGraphics

/// A binary tree of terminal panes. Adapted from Ghostty's `SplitTree` (see
/// `macos/Sources/Features/Splits/SplitTree.swift`), simplified for kterm:
/// leaves are `Terminal`s, no Codable/undo, and view bounds come from each
/// leaf's `SurfaceView`.
struct SplitTree {
    let root: Node?
    /// When set, only this node is shown (zoomed to fill the tab).
    let zoomed: Node?

    indirect enum Node {
        case leaf(Terminal)
        case split(Split)

        struct Split {
            let direction: Direction
            let ratio: Double
            let left: Node
            let right: Node
        }
    }

    /// Layout direction of a split node.
    /// - horizontal: left | right
    /// - vertical: top / bottom
    enum Direction {
        case horizontal
        case vertical
    }

    enum NewDirection {
        case left, right, down, up
    }

    enum FocusDirection {
        case previous
        case next
        case spatial(Spatial.Direction)
    }

    enum SplitError: Error {
        case viewNotFound
    }

    struct Spatial {
        let slots: [Slot]

        struct Slot {
            let node: Node
            let bounds: CGRect
        }

        enum Direction {
            case left, right, up, down
        }
    }

    var isEmpty: Bool { root == nil }
    var isSplit: Bool {
        if case .split = root { return true }
        return false
    }

    init(root: Node? = nil, zoomed: Node? = nil) {
        self.root = root
        self.zoomed = zoomed
    }

    init(terminal: Terminal) {
        self.init(root: .leaf(terminal), zoomed: nil)
    }

    /// All leaf terminals in left-to-right, top-to-bottom tree order.
    var terminals: [Terminal] { root?.leaves() ?? [] }

    func contains(_ terminal: Terminal) -> Bool {
        root?.node(of: terminal) != nil
    }

    func contains(_ node: Node) -> Bool {
        root?.path(to: node) != nil
    }

    func node(of terminal: Terminal) -> Node? {
        root?.node(of: terminal)
    }

    /// Insert `terminal` by splitting the leaf that holds `at`.
    func inserting(_ terminal: Terminal, at: Terminal, direction: NewDirection) throws -> SplitTree {
        guard let root else { throw SplitError.viewNotFound }
        return SplitTree(
            root: try root.inserting(terminal, at: at, direction: direction),
            zoomed: nil)
    }

    /// Remove a leaf/split node; its sibling takes the parent's place.
    func removing(_ target: Node) -> SplitTree {
        guard let root else { return self }
        if root == target { return SplitTree() }
        let newRoot = root.remove(target)
        let newZoomed: Node? = (zoomed == target) ? nil : zoomed
        return SplitTree(root: newRoot, zoomed: newZoomed)
    }

    func replacing(node: Node, with newNode: Node) throws -> SplitTree {
        guard let root, let path = root.path(to: node) else {
            throw SplitError.viewNotFound
        }
        let newRoot = try root.replacingNode(at: path, with: newNode)
        let newZoomed: Node? = (zoomed == node) ? newNode : zoomed
        return SplitTree(root: newRoot, zoomed: newZoomed)
    }

    func focusTarget(for direction: FocusDirection, from currentNode: Node) -> Terminal? {
        guard let root else { return nil }

        switch direction {
        case .previous:
            let leaves = root.leaves()
            let current = currentNode.leftmostLeaf()
            guard let idx = leaves.firstIndex(where: { $0 === current }) else { return nil }
            return leaves[(idx - 1 + leaves.count) % leaves.count]

        case .next:
            let leaves = root.leaves()
            let current = currentNode.rightmostLeaf()
            guard let idx = leaves.firstIndex(where: { $0 === current }) else { return nil }
            return leaves[(idx + 1) % leaves.count]

        case .spatial(let spatialDirection):
            let spatial = root.spatial()
            let nodes = spatial.slots(in: spatialDirection, from: currentNode)
            guard !nodes.isEmpty else { return nil }
            let best = nodes.first(where: {
                if case .leaf = $0.node { return true }
                return false
            }) ?? nodes[0]
            switch best.node {
            case .leaf(let term):
                return term
            case .split:
                switch spatialDirection {
                case .up, .left: return best.node.leftmostLeaf()
                case .down, .right: return best.node.rightmostLeaf()
                }
            }
        }
    }

    func equalized() -> SplitTree {
        guard let root else { return self }
        return SplitTree(root: root.equalize(), zoomed: zoomed)
    }

    /// Resize the nearest parent split of `node` by `pixels` in `direction`.
    func resizing(node: Node, by pixels: UInt16, in direction: Spatial.Direction,
                  with bounds: CGRect) throws -> SplitTree {
        guard let root, let path = root.path(to: node) else {
            throw SplitError.viewNotFound
        }

        let targetDirection: Direction = switch direction {
        case .up, .down: .vertical
        case .left, .right: .horizontal
        }

        var splitPath: Node.Path?
        var splitNode: Node?
        for i in stride(from: path.components.count - 1, through: 0, by: -1) {
            let parentPath = Node.Path(components: Array(path.components.prefix(i)))
            if let parent = root.node(at: parentPath), case .split(let split) = parent,
               split.direction == targetDirection {
                splitPath = parentPath
                splitNode = parent
                break
            }
        }

        guard let splitPath, let splitNode, case .split(let split) = splitNode else {
            throw SplitError.viewNotFound
        }

        let spatial = root.spatial(within: bounds.size)
        guard let splitSlot = spatial.slots.first(where: { $0.node == splitNode }) else {
            throw SplitError.viewNotFound
        }

        let offset = Double(pixels)
        let newRatio: Double
        switch (split.direction, direction) {
        case (.horizontal, .left):
            newRatio = max(0.1, min(0.9, split.ratio - offset / splitSlot.bounds.width))
        case (.horizontal, .right):
            newRatio = max(0.1, min(0.9, split.ratio + offset / splitSlot.bounds.width))
        case (.vertical, .up):
            newRatio = max(0.1, min(0.9, split.ratio - offset / splitSlot.bounds.height))
        case (.vertical, .down):
            newRatio = max(0.1, min(0.9, split.ratio + offset / splitSlot.bounds.height))
        default:
            throw SplitError.viewNotFound
        }

        let replaced = Node.split(.init(
            direction: split.direction, ratio: newRatio, left: split.left, right: split.right))
        return SplitTree(root: try root.replacingNode(at: splitPath, with: replaced), zoomed: nil)
    }

    func viewBounds() -> CGSize {
        root?.viewBounds() ?? .zero
    }
}

// MARK: - Node helpers

extension SplitTree.Node: Equatable {
    struct Path {
        enum Component { case left, right }
        var components: [Component]
        var isEmpty: Bool { components.isEmpty }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.leaf(a), .leaf(b)): return a === b
        case let (.split(a), .split(b)): return a == b
        default: return false
        }
    }

    func leaves() -> [Terminal] {
        switch self {
        case .leaf(let t): return [t]
        case .split(let s): return s.left.leaves() + s.right.leaves()
        }
    }

    func leftmostLeaf() -> Terminal {
        switch self {
        case .leaf(let t): return t
        case .split(let s): return s.left.leftmostLeaf()
        }
    }

    func rightmostLeaf() -> Terminal {
        switch self {
        case .leaf(let t): return t
        case .split(let s): return s.right.rightmostLeaf()
        }
    }

    func node(of terminal: Terminal) -> SplitTree.Node? {
        switch self {
        case .leaf(let t):
            return t === terminal ? self : nil
        case .split(let s):
            return s.left.node(of: terminal) ?? s.right.node(of: terminal)
        }
    }

    func path(to node: Self) -> Path? {
        var components: [Path.Component] = []
        func search(_ current: Self) -> Bool {
            if current == node { return true }
            guard case .split(let s) = current else { return false }
            components.append(.left)
            if search(s.left) { return true }
            components.removeLast()
            components.append(.right)
            if search(s.right) { return true }
            components.removeLast()
            return false
        }
        return search(self) ? Path(components: components) : nil
    }

    func node(at path: Path) -> Self? {
        var current = self
        for component in path.components {
            guard case .split(let s) = current else { return nil }
            current = component == .left ? s.left : s.right
        }
        return current
    }

    func inserting(_ terminal: Terminal, at: Terminal, direction: SplitTree.NewDirection) throws -> Self {
        guard let path = path(to: .leaf(at)) else { throw SplitTree.SplitError.viewNotFound }

        let splitDirection: SplitTree.Direction
        let newOnLeft: Bool
        switch direction {
        case .left:  splitDirection = .horizontal; newOnLeft = true
        case .right: splitDirection = .horizontal; newOnLeft = false
        case .up:    splitDirection = .vertical;   newOnLeft = true
        case .down:  splitDirection = .vertical;   newOnLeft = false
        }

        let newLeaf: Self = .leaf(terminal)
        let existing: Self = .leaf(at)
        let split: Self = .split(.init(
            direction: splitDirection,
            ratio: 0.5,
            left: newOnLeft ? newLeaf : existing,
            right: newOnLeft ? existing : newLeaf))
        return try replacingNode(at: path, with: split)
    }

    func replacingNode(at path: Path, with newNode: Self) throws -> Self {
        if path.isEmpty { return newNode }

        func replace(_ current: Self, offset: Int) throws -> Self {
            if offset >= path.components.count { return newNode }
            guard case .split(let s) = current else { throw SplitTree.SplitError.viewNotFound }
            switch path.components[offset] {
            case .left:
                return .split(.init(
                    direction: s.direction, ratio: s.ratio,
                    left: try replace(s.left, offset: offset + 1), right: s.right))
            case .right:
                return .split(.init(
                    direction: s.direction, ratio: s.ratio,
                    left: s.left, right: try replace(s.right, offset: offset + 1)))
            }
        }
        return try replace(self, offset: 0)
    }

    func remove(_ target: Self) -> Self? {
        if self == target { return nil }
        switch self {
        case .leaf:
            return self
        case .split(let s):
            let newLeft = s.left.remove(target)
            let newRight = s.right.remove(target)
            switch (newLeft, newRight) {
            case (nil, nil): return nil
            case (nil, let r?): return r
            case (let l?, nil): return l
            case (let l?, let r?):
                return .split(.init(direction: s.direction, ratio: s.ratio, left: l, right: r))
            }
        }
    }

    func resizing(to ratio: Double) -> Self {
        switch self {
        case .leaf: return self
        case .split(let s):
            return .split(.init(direction: s.direction, ratio: ratio, left: s.left, right: s.right))
        }
    }

    func equalize() -> Self {
        equalizeWithWeight().node
    }

    private func equalizeWithWeight() -> (node: Self, weight: Int) {
        switch self {
        case .leaf:
            return (self, 1)
        case .split(let s):
            let leftWeight = s.left.weightForDirection(s.direction)
            let rightWeight = s.right.weightForDirection(s.direction)
            let total = leftWeight + rightWeight
            let ratio = Double(leftWeight) / Double(total)
            let (leftNode, _) = s.left.equalizeWithWeight()
            let (rightNode, _) = s.right.equalizeWithWeight()
            return (.split(.init(direction: s.direction, ratio: ratio,
                                 left: leftNode, right: rightNode)), total)
        }
    }

    private func weightForDirection(_ direction: SplitTree.Direction) -> Int {
        switch self {
        case .leaf: return 1
        case .split(let s):
            if s.direction == direction {
                return s.left.weightForDirection(direction) + s.right.weightForDirection(direction)
            }
            return 1
        }
    }

    func viewBounds() -> CGSize {
        switch self {
        case .leaf(let t):
            return t.surfaceView.bounds.size
        case .split(let s):
            let l = s.left.viewBounds()
            let r = s.right.viewBounds()
            switch s.direction {
            case .horizontal:
                return CGSize(width: l.width + r.width, height: max(l.height, r.height))
            case .vertical:
                return CGSize(width: max(l.width, r.width), height: l.height + r.height)
            }
        }
    }

    // MARK: Spatial

    func spatial(within bounds: CGSize? = nil) -> SplitTree.Spatial {
        let width: Double
        let height: Double
        if let bounds {
            width = bounds.width
            height = bounds.height
        } else {
            let (w, h) = dimensions()
            width = Double(w)
            height = Double(h)
        }
        return SplitTree.Spatial(slots: spatialSlots(in: CGRect(x: 0, y: 0, width: width, height: height)))
    }

    private func dimensions() -> (width: UInt, height: UInt) {
        switch self {
        case .leaf: return (1, 1)
        case .split(let s):
            let l = s.left.dimensions()
            let r = s.right.dimensions()
            switch s.direction {
            case .horizontal: return (l.width + r.width, max(l.height, r.height))
            case .vertical: return (max(l.width, r.width), l.height + r.height)
            }
        }
    }

    private func spatialSlots(in bounds: CGRect) -> [SplitTree.Spatial.Slot] {
        switch self {
        case .leaf:
            return [.init(node: self, bounds: bounds)]
        case .split(let s):
            let leftBounds: CGRect
            let rightBounds: CGRect
            switch s.direction {
            case .horizontal:
                let x = bounds.minX + bounds.width * s.ratio
                leftBounds = CGRect(x: bounds.minX, y: bounds.minY,
                                    width: bounds.width * s.ratio, height: bounds.height)
                rightBounds = CGRect(x: x, y: bounds.minY,
                                     width: bounds.width * (1 - s.ratio), height: bounds.height)
            case .vertical:
                let y = bounds.minY + bounds.height * s.ratio
                leftBounds = CGRect(x: bounds.minX, y: bounds.minY,
                                    width: bounds.width, height: bounds.height * s.ratio)
                rightBounds = CGRect(x: bounds.minX, y: y,
                                     width: bounds.width, height: bounds.height * (1 - s.ratio))
            }
            var slots: [SplitTree.Spatial.Slot] = [.init(node: self, bounds: bounds)]
            slots += s.left.spatialSlots(in: leftBounds)
            slots += s.right.spatialSlots(in: rightBounds)
            return slots
        }
    }

    /// Hashable structural identity for SwiftUI `.id(...)`.
    var structuralIdentity: StructuralIdentity { StructuralIdentity(self) }

    struct StructuralIdentity: Hashable {
        private let node: SplitTree.Node
        init(_ node: SplitTree.Node) { self.node = node }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.node.isStructurallyEqual(to: rhs.node)
        }

        func hash(into hasher: inout Hasher) {
            node.hashStructure(into: &hasher)
        }
    }

    fileprivate func isStructurallyEqual(to other: Self) -> Bool {
        switch (self, other) {
        case let (.leaf(a), .leaf(b)): return a === b
        case let (.split(a), .split(b)):
            return a.direction == b.direction
                && a.left.isStructurallyEqual(to: b.left)
                && a.right.isStructurallyEqual(to: b.right)
        default: return false
        }
    }

    fileprivate func hashStructure(into hasher: inout Hasher) {
        switch self {
        case .leaf(let t):
            hasher.combine(0 as UInt8)
            hasher.combine(ObjectIdentifier(t))
        case .split(let s):
            hasher.combine(1 as UInt8)
            hasher.combine(s.direction == .horizontal)
            s.left.hashStructure(into: &hasher)
            s.right.hashStructure(into: &hasher)
        }
    }
}

// MARK: - Spatial navigation

extension SplitTree.Spatial {
    func slots(in direction: Direction, from referenceNode: SplitTree.Node) -> [Slot] {
        guard let ref = slots.first(where: { $0.node == referenceNode }) else { return [] }

        func distance(_ a: CGRect, _ b: CGRect) -> Double {
            let dx = b.minX - a.minX
            let dy = b.minY - a.minY
            return sqrt(dx * dx + dy * dy)
        }

        let filtered: [Slot]
        switch direction {
        case .left:
            filtered = slots.filter { $0.node != referenceNode && $0.bounds.maxX <= ref.bounds.minX }
        case .right:
            filtered = slots.filter { $0.node != referenceNode && $0.bounds.minX >= ref.bounds.maxX }
        case .up:
            filtered = slots.filter { $0.node != referenceNode && $0.bounds.maxY <= ref.bounds.minY }
        case .down:
            filtered = slots.filter { $0.node != referenceNode && $0.bounds.minY >= ref.bounds.maxY }
        }
        return filtered.sorted { distance(ref.bounds, $0.bounds) < distance(ref.bounds, $1.bounds) }
    }
}

extension SplitTree.Node.Split: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.direction == rhs.direction
            && lhs.ratio == rhs.ratio
            && lhs.left == rhs.left
            && lhs.right == rhs.right
    }
}
