import Foundation
import Observation

/// Owns one open project: the payload, its undo history and autosave.
@MainActor
@Observable
public final class ProjectController<P: ProjectPayload> {
    public let url: URL
    public private(set) var header: ProjectHeader
    public var payload: P { didSet { if payload != oldValue { scheduleAutosave() } } }
    public private(set) var history = UndoHistory<P>()
    public private(set) var lastSaved: Date?
    public var lastError: StudioError?

    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored public var autosaveDelay: Duration = .seconds(1.5)

    public init(url: URL, store: ProjectStore = .shared) throws {
        self.url = url
        self.store = store
        let file = try store.load(P.self, from: url)
        header = file.header
        payload = file.payload
    }

    public var mediaURL: URL { store.mediaURL(url) }
    public func resolve(_ relative: String) -> URL { store.resolve(relative, in: url) }
    public func importMedia(_ source: URL) throws -> String { try store.importMedia(source, into: url) }

    /// Applies `change` as one undoable step.
    public func mutate(_ label: String, _ change: (inout P) -> Void) {
        let before = payload
        var p = payload
        change(&p)
        guard p != before else { return }
        history.record(before, label: label)
        payload = p
    }

    /// Continuous edits (drags): one undo step for the whole gesture.
    public func beginGesture() { history.beginCoalescing() }
    public func endGesture() { history.endCoalescing() }

    public func undo() {
        if let s = history.undo(current: payload) { payload = s }
    }

    public func redo() {
        if let s = history.redo(current: payload) { payload = s }
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    public func save() {
        autosaveTask?.cancel()
        do {
            try store.write(ProjectFile(header: header, payload: payload), to: url)
            header.modified = .now
            lastSaved = .now
        } catch {
            lastError = .io(error.localizedDescription)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}
