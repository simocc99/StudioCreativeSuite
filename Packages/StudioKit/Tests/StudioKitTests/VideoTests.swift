import AVFoundation
@testable import StudioAudio
@testable import StudioCore
@testable import StudioVideo
import XCTest

final class VideoTests: XCTestCase {
    func testTimelineEditing() {
        var p = VideoProject()
        let a = MediaItem(path: "a.mp4", name: "a", duration: 4, hasVideo: true, hasAudio: false)
        let b = MediaItem(path: "b.mp4", name: "b", duration: 3, hasVideo: true, hasAudio: false)
        let ia = p.addClip(a, track: 0)!
        let ib = p.addClip(b, track: 0)!
        XCTAssertEqual(p.clip(ib)!.start, 4, accuracy: 1e-9)
        let right = p.split(ia, at: 1.5)!
        check("video.split", abs(p.clip(ia)!.duration - 1.5) < 1e-9 && abs(p.clip(right)!.sourceStart - 1.5) < 1e-9,
              expected: "1.5 s + 2.5 s from 1.5 s", observed: "\(p.clip(ia)!.duration), src \(p.clip(right)!.sourceStart)")
        p.delete([right], ripple: true)
        check("video.ripple", abs(p.clip(ib)!.start - 1.5) < 1e-9, expected: "b moves to 1.5 s", observed: "\(p.clip(ib)!.start)")
        p.trimEnd(ia, by: 10, sourceLength: 4)
        check("video.trim.bound", abs(p.clip(ia)!.duration - 4) < 1e-9 && p.clip(ib)!.start >= p.clip(ia)!.end - 1e-9,
              expected: "trim limited to source, no overlap", observed: "dur \(p.clip(ia)!.duration) b@\(p.clip(ib)!.start)")
        p.setSpeed(ib, 2)
        XCTAssertEqual(p.clip(ib)!.duration, 1.5, accuracy: 1e-9)
        p.move(ib, to: 0.5)
        let clips = p.tracks[0].clips
        check("video.move.noOverlap", zip(clips, clips.dropFirst()).allSatisfy { $1.start >= $0.end - $1.transitionIn - 1e-9 },
              expected: "clips never overlap", observed: clips.map { "\($0.start)-\($0.end)" }.joined(separator: " "))
        XCTAssertNil(p.addClip(MediaItem(path: "s.wav", name: "s", duration: 1, hasVideo: false, hasAudio: true), track: 0), "audio-only on a video track")
        XCTAssertEqual(p.importSRT("1\n00:00:01,000 --> 00:00:02,500\nCiao\n\n2\n00:00:03,000 --> 00:00:04,000\nMondo\n"), 2)
    }

    /// Two coloured clips + a tone on an audio track → H.264 export: duration, frames and audio checked.
    func testMultiClipExport() async throws {
        let dir = Fixtures.tempDir("video")
        let media = dir.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try await Fixtures.movie(media.appendingPathComponent("red.mp4"), seconds: 2, color: RGBAColor(1, 0, 0))
        try await Fixtures.movie(media.appendingPathComponent("blue.mp4"), seconds: 2, color: RGBAColor(0, 0, 1))
        try Fixtures.tone(media.appendingPathComponent("tone.wav"), seconds: 3.5, freq: 440)

        var p = VideoProject()
        p.renderWidth = 640
        p.renderHeight = 360
        for (n, v) in [("red.mp4", true), ("blue.mp4", true), ("tone.wav", false)] {
            let item = try await MediaProbe.probe(media.appendingPathComponent(n), relativePath: "Media/\(n)")
            XCTAssertEqual(item.hasVideo, v)
            p.media.append(item)
        }
        p.addClip(p.media[0], track: 0)
        let blue = p.addClip(p.media[1], track: 0)!
        p.addClip(p.media[2], track: 2)
        p.setTransition(blue, 0.5)
        p.addTitle("Titolo", at: 0, duration: 1)
        XCTAssertEqual(p.duration, 3.5, accuracy: 0.01)

        let built = try await CompositionBuilder.build(p, projectURL: dir)
        let presets = await VideoExporter.availablePresets(for: built)
        check("video.presets", presets.contains(.h264_720), expected: "H.264 available", observed: presets.map(\.rawValue).joined(separator: ","))
        let out = dir.appendingPathComponent("out.mp4")
        try await VideoExporter.export(built, preset: .h264_720, to: out) { _ in }

        let asset = AVURLAsset(url: out)
        let d = try await asset.load(.duration).seconds
        let vt = try await asset.loadTracks(withMediaType: .video)
        let at = try await asset.loadTracks(withMediaType: .audio)
        check("video.export.duration", abs(d - 3.5) < 0.1 && !vt.isEmpty && !at.isEmpty,
              expected: "3.5 s with video + audio tracks", observed: String(format: "%.2f s, %d video, %d audio", d, vt.count, at.count))
        let f1 = Fixtures.average(try await Fixtures.frame(out, at: 1.2))
        let f2 = Fixtures.average(try await Fixtures.frame(out, at: 3.0))
        check("video.export.frames", f1.0 > 150 && f1.2 < 80 && f2.2 > 150 && f2.0 < 80, expected: "red at 1.2 s, blue at 3.0 s",
              observed: "\(Int(f1.0)),\(Int(f1.1)),\(Int(f1.2)) / \(Int(f2.0)),\(Int(f2.1)),\(Int(f2.2))")
        // in the cross dissolve both colours mix
        let mid = Fixtures.average(try await Fixtures.frame(out, at: 1.75))
        check("video.export.dissolve", mid.0 > 40 && mid.2 > 40, expected: "red and blue mixed at 1.75 s", observed: "\(Int(mid.0)),\(Int(mid.2))")
    }

    func testSaveReopen() throws {
        let store = ProjectStore(root: Fixtures.tempDir("vstore"))
        let url = try store.create(VideoProject.self, name: "Montaggio")
        var f = try store.load(VideoProject.self, from: url)
        f.payload.addMarker(at: 2)
        f.payload.media = [MediaItem(path: "x", name: "x", duration: 5, hasVideo: true, hasAudio: true)]
        f.payload.addClip(f.payload.media[0], track: 0)
        f.payload.tracks[0].clips[0].keyframes = [ClipKeyframe(time: 1, value: ClipTransform())]
        try store.write(f, to: url)
        let back = try store.load(VideoProject.self, from: url)
        check("video.reopen", back.payload == f.payload, expected: "identical project after reopen", observed: back.payload == f.payload ? "identical" : "different")
    }
}

final class TimecodeTests: XCTestCase {
    func testTimecodeRounding() {
        check("video.timecode", timecode(0.99999) == "00:01:00" && timecode(61.5) == "01:01:15", expected: "00:01:00, 01:01:15",
              observed: "\(timecode(0.99999)), \(timecode(61.5))")
    }
}
