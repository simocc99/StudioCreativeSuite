import AVFoundation
import StudioCore

public enum VideoExportPreset: String, CaseIterable, Identifiable, Sendable {
    case h264_1080, h264_720, hevc_1080, hevc_2160, prores422, audioM4A

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .h264_1080: "H.264 1080p (.mp4)"
        case .h264_720: "H.264 720p (.mp4)"
        case .hevc_1080: "HEVC 1080p (.mov)"
        case .hevc_2160: "HEVC 4K (.mov)"
        case .prores422: "Apple ProRes 422 (.mov)"
        case .audioM4A: "Solo audio AAC (.m4a)"
        }
    }

    var presetName: String {
        switch self {
        case .h264_1080: AVAssetExportPreset1920x1080
        case .h264_720: AVAssetExportPreset1280x720
        case .hevc_1080: AVAssetExportPresetHEVC1920x1080
        case .hevc_2160: AVAssetExportPresetHEVC3840x2160
        case .prores422: AVAssetExportPresetAppleProRes422LPCM
        case .audioM4A: AVAssetExportPresetAppleM4A
        }
    }

    var fileType: AVFileType {
        switch self {
        case .h264_1080, .h264_720: .mp4
        case .hevc_1080, .hevc_2160, .prores422: .mov
        case .audioM4A: .m4a
        }
    }

    public var fileExtension: String {
        switch fileType {
        case .mp4: "mp4"
        case .m4a: "m4a"
        default: "mov"
        }
    }
}

public enum VideoExporter {
    /// Presets this device can actually export the composition with (checked, not assumed).
    public static func availablePresets(for built: BuiltComposition) async -> [VideoExportPreset] {
        var out: [VideoExportPreset] = []
        for p in VideoExportPreset.allCases {
            if await AVAssetExportSession.compatibility(ofExportPreset: p.presetName, with: built.composition, outputFileType: p.fileType) {
                out.append(p)
            }
        }
        return out
    }

    /// Renders the composition (same compositor as the preview) to `url`.
    public static func export(_ built: BuiltComposition, preset: VideoExportPreset, to url: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let s = AVAssetExportSession(asset: built.composition, presetName: preset.presetName) else {
            throw StudioError.notAvailable("preset \(preset.title)")
        }
        if preset != .audioM4A { s.videoComposition = built.videoComposition }
        s.audioMix = built.audioMix
        s.audioTimePitchAlgorithm = .spectral
        try? FileManager.default.removeItem(at: url)
        let monitor = Task {
            for await state in s.states(updateInterval: 0.2) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        do {
            try await s.export(to: url, as: preset.fileType)
        } catch is CancellationError {
            throw StudioError.cancelled
        } catch {
            throw StudioError.engine("esportazione video: \(error.localizedDescription)")
        }
        progress(1)
    }
}
