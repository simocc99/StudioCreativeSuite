import Foundation

/// Snapshot-based undo/redo for value-type documents.
///
/// Editors call `record(_:label:)` with the state *before* a change; continuous gestures (slider
/// drags, strokes) call `beginCoalescing` / `endCoalescing` so a whole drag is one step.
public struct UndoHistory<State: Equatable>: Equatable {
    public struct Entry: Equatable {
        public let state: State
        public let label: String
    }

    public private(set) var past: [Entry] = []
    public private(set) var future: [Entry] = []
    public var limit: Int
    private var coalescing = false

    public init(limit: Int = 200) { self.limit = limit }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoLabel: String? { past.last?.label }
    public var redoLabel: String? { future.last?.label }

    /// Records `before` as an undo point (ignored while coalescing after the first record).
    public mutating func record(_ before: State, label: String) {
        if coalescing, !past.isEmpty, past.last?.label == label { return }
        if past.last?.state == before, past.last?.label == label { return }
        past.append(Entry(state: before, label: label))
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    public mutating func beginCoalescing() { coalescing = true }
    public mutating func endCoalescing() { coalescing = false }

    /// Returns the state to restore, given the current one.
    public mutating func undo(current: State) -> State? {
        guard let e = past.popLast() else { return nil }
        future.append(Entry(state: current, label: e.label))
        return e.state
    }

    public mutating func redo(current: State) -> State? {
        guard let e = future.popLast() else { return nil }
        past.append(Entry(state: current, label: e.label))
        return e.state
    }

    public mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
