import Foundation

/// Editing operations on a `VideoProject`. Pure value-type functions: the editor wraps them in
/// undoable `mutate` calls and the tests call them directly.
public extension VideoProject {
    static let minClipDuration = 1.0 / 30

    func trackIndex(of clip: UUID) -> (Int, Int)? {
        for (ti, t) in tracks.enumerated() {
            if let ci = t.clips.firstIndex(where: { $0.id == clip }) { return (ti, ci) }
        }
        return nil
    }

    func clip(_ id: UUID) -> Clip? {
        trackIndex(of: id).map { tracks[$0.0].clips[$0.1] }
    }

    /// Appends media to a track at `time` (or at the track's end when nil). Returns the new clip id.
    @discardableResult
    mutating func addClip(_ item: MediaItem, track: Int, at time: Double? = nil) -> UUID? {
        guard tracks.indices.contains(track), !tracks[track].locked else { return nil }
        if tracks[track].kind == .video && !item.hasVideo { return nil }
        if tracks[track].kind == .audio && !item.hasAudio { return nil }
        let start = time ?? (tracks[track].clips.map(\.end).max() ?? 0)
        let c = Clip(media: item.path, start: max(0, start), sourceDuration: item.duration,
                     hasVideo: tracks[track].kind == .video && item.hasVideo, hasAudio: item.hasAudio)
        tracks[track].clips.append(c)
        resolveOverlaps(track: track, keeping: c.id)
        return c.id
    }

    /// Splits a clip at timeline time `t`. Returns the id of the right half.
    @discardableResult
    mutating func split(_ id: UUID, at t: Double) -> UUID? {
        guard let (ti, ci) = trackIndex(of: id), !tracks[ti].locked else { return nil }
        let c = tracks[ti].clips[ci]
        guard t > c.start + Self.minClipDuration, t < c.end - Self.minClipDuration else { return nil }
        let leftTimeline = t - c.start
        let leftSource = leftTimeline * c.speed
        var left = c, right = c
        left.sourceDuration = leftSource
        left.fadeOut = 0
        left.keyframes = c.keyframes.filter { $0.time <= leftTimeline }
        right.id = UUID()
        right.start = t
        right.sourceStart = c.sourceStart + leftSource
        right.sourceDuration = c.sourceDuration - leftSource
        right.fadeIn = 0
        right.transitionIn = 0
        right.keyframes = c.keyframes.filter { $0.time >= leftTimeline }.map { ClipKeyframe(time: $0.time - leftTimeline, value: $0.value) }
        right.transform = c.transform(at: t)
        tracks[ti].clips[ci] = left
        tracks[ti].clips.insert(right, at: ci + 1)
        return right.id
    }

    /// Splits every clip under the playhead on unlocked tracks.
    mutating func splitAll(at t: Double) {
        for ti in tracks.indices where !tracks[ti].locked {
            for c in tracks[ti].clips where c.start < t && c.end > t { split(c.id, at: t) }
        }
    }

    /// Moves the in-point by `delta` timeline seconds (positive trims away the head), within the source.
    mutating func trimStart(_ id: UUID, by delta: Double, sourceLength: Double) {
        guard let (ti, ci) = trackIndex(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        var d = delta * c.speed
        d = max(d, -c.sourceStart) // cannot extend before the source's first frame
        d = min(d, c.sourceDuration - Self.minClipDuration * c.speed)
        c.sourceStart += d
        c.sourceDuration -= d
        c.start += d / c.speed
        if c.start < 0 { c.sourceStart -= c.start * c.speed; c.sourceDuration += c.start * c.speed; c.start = 0 }
        tracks[ti].clips[ci] = c
        _ = sourceLength
        resolveOverlaps(track: ti, keeping: id)
    }

    /// Moves the out-point by `delta` timeline seconds (positive extends), within the source.
    mutating func trimEnd(_ id: UUID, by delta: Double, sourceLength: Double) {
        guard let (ti, ci) = trackIndex(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        let maxSource = sourceLength - c.sourceStart
        c.sourceDuration = min(maxSource, max(Self.minClipDuration * c.speed, c.sourceDuration + delta * c.speed))
        tracks[ti].clips[ci] = c
        resolveOverlaps(track: ti, keeping: id)
    }

    /// Deletes clips. With `ripple`, later clips on the same track move left to close the gap.
    mutating func delete(_ ids: Set<UUID>, ripple: Bool) {
        for ti in tracks.indices where !tracks[ti].locked {
            let removed = tracks[ti].clips.filter { ids.contains($0.id) }.sorted { $0.start > $1.start }
            guard !removed.isEmpty else { continue }
            tracks[ti].clips.removeAll { ids.contains($0.id) }
            if ripple {
                for r in removed {
                    for i in tracks[ti].clips.indices where tracks[ti].clips[i].start >= r.end - 1e-9 {
                        tracks[ti].clips[i].start -= r.duration
                    }
                }
            }
        }
        titles.removeAll { ids.contains($0.id) }
    }

    /// Moves a clip to `start` on `track` (same kind only). Overlaps are resolved by pushing later clips right.
    mutating func move(_ id: UUID, to start: Double, track newTrack: Int? = nil) {
        guard let (ti, ci) = trackIndex(of: id), !tracks[ti].locked else { return }
        var c = tracks[ti].clips[ci]
        c.start = max(0, start)
        let dest = newTrack ?? ti
        guard tracks.indices.contains(dest), tracks[dest].kind == tracks[ti].kind, !tracks[dest].locked else { return }
        tracks[ti].clips.remove(at: ci)
        if c.transitionIn > 0, dest != ti { c.transitionIn = 0 }
        tracks[dest].clips.append(c)
        resolveOverlaps(track: dest, keeping: id)
    }

    /// Sets the cross-dissolve with the previous clip: the clip (and the later clips on its track) move
    /// left so the two overlap by `seconds`. Limited to half of either clip.
    mutating func setTransition(_ id: UUID, _ seconds: Double) {
        guard let (ti, _) = trackIndex(of: id), !tracks[ti].locked else { return }
        resolveOverlaps(track: ti)
        guard let ci = tracks[ti].clips.firstIndex(where: { $0.id == id }), ci > 0 else { return }
        let prev = tracks[ti].clips[ci - 1], c = tracks[ti].clips[ci]
        let gap = c.start - (prev.end - c.transitionIn)
        guard gap < 1e-6 else { return } // only clips that touch can dissolve
        let new = max(0, min(seconds, prev.duration * 0.5, c.duration * 0.5))
        let shift = new - c.transitionIn
        for i in ci ..< tracks[ti].clips.count { tracks[ti].clips[i].start -= shift }
        tracks[ti].clips[ci].transitionIn = new
    }

    mutating func setSpeed(_ id: UUID, _ speed: Double) {
        guard let (ti, ci) = trackIndex(of: id) else { return }
        tracks[ti].clips[ci].speed = min(8, max(0.1, speed))
        resolveOverlaps(track: ti, keeping: id)
    }

    mutating func update(_ id: UUID, _ change: (inout Clip) -> Void) {
        guard let (ti, ci) = trackIndex(of: id) else { return }
        change(&tracks[ti].clips[ci])
        resolveOverlaps(track: ti, keeping: id)
    }

    /// Keeps the clips of a track sorted and non-overlapping (except a clip's `transitionIn`).
    /// The clip `keeping` stays where it was put; others after it are pushed right.
    mutating func resolveOverlaps(track ti: Int, keeping: UUID? = nil) {
        var clips = tracks[ti].clips.sorted { a, b in
            if abs(a.start - b.start) < 1e-9 { return a.id == keeping }
            return a.start < b.start
        }
        for i in clips.indices.dropFirst() {
            let prev = clips[i - 1]
            let overlap = min(clips[i].transitionIn, prev.duration * 0.5, clips[i].duration * 0.5)
            clips[i].transitionIn = max(0, overlap)
            let minStart = prev.end - clips[i].transitionIn
            if clips[i].start < minStart - 1e-9 { clips[i].start = minStart }
        }
        tracks[ti].clips = clips
    }

    mutating func addMarker(at t: Double) {
        markers.append(Marker(time: t, name: "Marcatore \(markers.count + 1)"))
        markers.sort { $0.time < $1.time }
    }

    @discardableResult
    mutating func addTitle(_ text: String, at t: Double, duration: Double = 3, subtitle: Bool = false) -> UUID {
        var title = TitleClip(text: text, start: t, duration: duration)
        if subtitle {
            title.isSubtitle = true
            title.fontSize = 48
            title.y = 0.9
        }
        titles.append(title)
        return title.id
    }

    /// Imports an SRT subtitle file as subtitle titles.
    mutating func importSRT(_ text: String) -> Int {
        var n = 0
        for block in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let a = Self.srtTime(parts[0]), let b = Self.srtTime(parts[1]), b > a else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n")
            addTitle(body, at: a, duration: b - a, subtitle: true)
            n += 1
        }
        return n
    }

    static func srtTime(_ s: String) -> Double? {
        let p = s.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let sec = Double(p[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    /// Clips active at time t on a track, ordered by start.
    func activeClips(track ti: Int, at t: Double) -> [Clip] {
        tracks[ti].clips.filter { $0.start <= t && $0.end > t }
    }

    /// Nearest edit point (clip edges, markers) to `t` within `tolerance`, for snapping.
    func snap(_ t: Double, tolerance: Double, excluding: UUID? = nil) -> Double {
        var points: [Double] = [0] + markers.map(\.time)
        for c in tracks.flatMap(\.clips) where c.id != excluding { points += [c.start, c.end] }
        let best = points.min { abs($0 - t) < abs($1 - t) }
        if let best, abs(best - t) <= tolerance { return best }
        return t
    }
}
