import ImageIO
import StudioAudio
import StudioCore
import StudioMotion
import StudioPhoto
import StudioVector
import StudioVideo
import SwiftUI
import UniformTypeIdentifiers

/// Demo content for automated screenshots (CI job "screenshots"). Started only by the launch
/// argument `-StudioScene <name>`; never in normal use. All content is generated here — no
/// personal files are read. Scenes: home, list, photo, raster, vector, paint, video, motion,
/// animation, audio, layout.
enum DemoScene {
    static var requested: String? { UserDefaults.standard.string(forKey: "StudioScene") }

    /// Builds one project per module (once per install) and returns where to open each one.
    @MainActor
    static func prepare(_ scene: String, state: AppState) async {
        let store = ProjectStore.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        state.reload()
        var urls = Dictionary(state.projects.map { ($0.header.kind, $0.url) }, uniquingKeysWith: { a, _ in a })

        if urls.isEmpty {
            let photoFile = tmp.appendingPathComponent("Tramonto sul lago.jpg")
            let landscape = Self.landscape(width: 3000, height: 2000)
            Self.writeJPEG(landscape, to: photoFile)

            if let u = state.create(.photo, name: "Tramonto sul lago"), var f = try? store.load(PhotoProject.self, from: u) {
                f.payload.source = try? store.importMedia(photoFile, into: u)
                try? store.write(f, to: u)
                Self.thumbnail(landscape, project: u)
                urls[.photo] = u
            }
            if let u = state.create(.raster, name: "Poster lago"), var f = try? store.load(RasterProject.self, from: u),
               let rel = try? store.importMedia(photoFile, into: u) {
                f.payload.width = 3000
                f.payload.height = 2000
                var tint = RasterLayer(name: "Tinta", content: .fill(RGBAColor(0.55, 0.35, 0.9)))
                tint.blend = .softLight
                tint.opacity = 0.5
                f.payload.layers = [RasterLayer(name: "Foto", content: .image(rel)), tint]
                try? store.write(f, to: u)
                Self.thumbnail(landscape, project: u)
                urls[.raster] = u
            }
            if let t = QuickTemplate.all.first, let u = state.create(.vector, name: t.name, template: t) {
                Self.thumbnail(VectorRenderer.image(t.document(), scale: 640 / max(t.width, t.height), opaque: true).cgImage, project: u)
                urls[.vector] = u
            }
            if let u = state.create(.motion, name: "Titolo animato"), var f = try? store.load(MotionProject.self, from: u) {
                var bg = MotionLayer(name: "Sfondo", kind: .solid)
                bg.color = RGBAColor(0.12, 0.1, 0.22)
                var star = MotionLayer(name: "Stella", kind: .star(points: 5))
                star.color = RGBAColor(0.55, 0.51, 0.94)
                star.rotation.keys = [Keyframe(time: 0, value: 0), Keyframe(time: 10, value: 180)]
                star.scale.keys = [Keyframe(time: 0, value: 60), Keyframe(time: 3, value: 100)]
                var title = MotionLayer(name: "Titolo", kind: .text("Studio", fontSize: 160))
                title.color = .white
                title.y = AnimatedValue(820)
                title.width = 1200
                title.height = 220
                title.opacity.keys = [Keyframe(time: 0, value: 0), Keyframe(time: 1.5, value: 100)]
                f.payload.layers = [bg, star, title]
                try? store.write(f, to: u)
                urls[.motion] = u
            }
            for m in [StudioModule.paint, .animation, .layout] {
                urls[m] = state.create(m, name: "\(m.title) di prova")
            }

            for m in [StudioModule.video, .audio] {
                urls[m] = state.create(m, name: m == .video ? "Montaggio di prova" : "Voce e musica")
            }
            state.reload()
        }

        switch scene {
        case "home": state.module = nil
        case "list": state.module = .photo
        default:
            guard let m = StudioModule(rawValue: scene), let u = urls[m] else { return }
            // video and audio media are imported by the editor on open (it probes them);
            // EditorHost imports only into an empty project, so relaunching is harmless
            var pending: URL?
            if m == .video { pending = await makeClip(in: tmp) }
            if m == .audio { pending = makeTone(in: tmp) }
            state.module = m
            state.path.append(EditorRoute.project(u, m, pendingImport: pending))
        }
    }

    private static func makeClip(in dir: URL) async -> URL? {
        let clip = dir.appendingPathComponent("Clip.mp4")
        do {
            if FileManager.default.fileExists(atPath: clip.path) { return clip }
            try await FrameVideoWriter.write(to: clip, width: 1280, height: 720, fps: 30, frameCount: 90) { i, ctx in
                let t = Double(i) / 90
                ctx.setFillColor(CGColor(srgbRed: 0.1 + 0.3 * t, green: 0.12, blue: 0.3, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
                ctx.setFillColor(CGColor(srgbRed: 0.55, green: 0.51, blue: 0.94, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: 130 + t * 870, y: 260, width: 200, height: 200))
            }
            return clip
        } catch { return nil }
    }

    private static func makeTone(in dir: URL) -> URL? {
        let tone = dir.appendingPathComponent("Tono.wav")
        let n = 48000 * 8
        let samples = (0 ..< n).map { i -> Float in
            let t = Double(i) / 48000
            return Float(0.4 * sin(2 * .pi * 220 * t) * (0.6 + 0.4 * sin(2 * .pi * 0.5 * t)))
        }
        do {
            try AudioIO.write(PCMBuffer(sampleRate: 48000, channels: [samples, samples]), to: tone, format: .wav16)
            return tone
        } catch { return nil }
    }

    /// Screenshots are taken in landscape, the way the editors are meant to be used.
    @MainActor
    static func requestLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
    }

    private static func thumbnail(_ image: CGImage?, project: URL) {
        if let image { ProjectStore.writeThumbnail(image, to: project) }
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        CGImageDestinationFinalize(d)
    }

    /// Synthetic landscape: sky gradient, sun, two mountain ridges, lake.
    private static func landscape(width w: Int, height h: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let W = CGFloat(w), H = CGFloat(h)
        let sky = CGGradient(colorsSpace: cs, colors: [
            CGColor(srgbRed: 0.98, green: 0.62, blue: 0.35, alpha: 1),
            CGColor(srgbRed: 0.55, green: 0.35, blue: 0.62, alpha: 1),
            CGColor(srgbRed: 0.12, green: 0.14, blue: 0.32, alpha: 1),
        ] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H * 0.35), end: CGPoint(x: 0, y: H), options: [.drawsBeforeStartLocation])
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.6, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: W * 0.62, y: H * 0.42, width: W * 0.09, height: W * 0.09))
        func ridge(_ base: CGFloat, _ amp: CGFloat, _ freq: CGFloat, _ color: CGColor) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: 0, through: W, by: 8) {
                let y = base + amp * (sin(x / W * freq * .pi) * 0.6 + sin(x / W * freq * 2.7 * .pi) * 0.4)
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: W, y: 0))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        ridge(H * 0.48, H * 0.08, 3, CGColor(srgbRed: 0.3, green: 0.22, blue: 0.38, alpha: 1))
        ridge(H * 0.38, H * 0.06, 5, CGColor(srgbRed: 0.14, green: 0.12, blue: 0.22, alpha: 1))
        let lake = CGGradient(colorsSpace: cs, colors: [
            CGColor(srgbRed: 0.08, green: 0.1, blue: 0.2, alpha: 1),
            CGColor(srgbRed: 0.45, green: 0.32, blue: 0.4, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H * 0.3))
        ctx.drawLinearGradient(lake, start: .zero, end: CGPoint(x: 0, y: H * 0.3), options: [])
        ctx.restoreGState()
        return ctx.makeImage()!
    }
}

/// Shown instead of RootView when a demo scene is requested.
struct DemoSceneView: View {
    let scene: String
    @State private var state = AppState()
    @State private var ready = false

    var body: some View {
        Group {
            if ready { RootView(state: state) } else { ProgressView("Preparazione della scena…") }
        }
        .task {
            DemoScene.requestLandscape()
            await DemoScene.prepare(scene, state: state)
            ready = true
        }
    }
}
