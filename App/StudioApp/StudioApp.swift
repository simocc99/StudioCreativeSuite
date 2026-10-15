import StudioAssets
import StudioAudio
import StudioCore
import StudioLayout
import StudioMotion
import StudioPaint
import StudioPDF
import StudioPhoto
import StudioVector
import StudioVideo
import SwiftUI

@main
struct StudioCreativeSuiteApp: App {
    var body: some Scene {
        WindowGroup {
            Group {
                if Benchmark.requested {
                    BenchmarkView()
                } else if let scene = DemoScene.requested {
                    DemoSceneView(scene: scene)
                } else {
                    RootView()
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

@MainActor
@Observable
final class AppState {
    var module: StudioModule? = nil
    var path = NavigationPath()
    var projects: [ProjectSummary] = []
    var error: String?

    func reload() { projects = ProjectStore.shared.list() }

    func projects(for m: StudioModule) -> [ProjectSummary] { projects.filter { $0.header.kind == m } }

    func create(_ m: StudioModule, name: String, template: QuickTemplate? = nil) -> URL? {
        do {
            let url: URL = switch m {
            case .photo: try ProjectStore.shared.create(PhotoProject.self, name: name)
            case .raster: try ProjectStore.shared.create(RasterProject.self, name: name)
            case .vector: try ProjectStore.shared.create(VectorProject.self, name: name)
            case .paint: try ProjectStore.shared.create(PaintProject.self, name: name)
            case .video: try ProjectStore.shared.create(VideoProject.self, name: name)
            case .motion: try ProjectStore.shared.create(MotionProject.self, name: name)
            case .animation: try ProjectStore.shared.create(AnimationProject.self, name: name)
            case .audio: try ProjectStore.shared.create(AudioProject.self, name: name)
            case .layout: try ProjectStore.shared.create(LayoutProject.self, name: name)
            case .pdf, .assets: throw StudioError.notAvailable("questo modulo non usa progetti")
            }
            if let template, m == .vector {
                var f = try ProjectStore.shared.load(VectorProject.self, from: url)
                f.payload = template.document()
                try ProjectStore.shared.write(f, to: url)
            }
            reload()
            return url
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// "Open in" from the asset library: a new project of that kind with the asset imported.
    func open(asset: Asset, file: URL, in m: StudioModule) {
        if m == .pdf {
            do {
                let copy = try PDFLibrary.importCopy(file)
                module = .pdf
                path = NavigationPath()
                path.append(EditorRoute.pdf(copy))
            } catch { self.error = error.localizedDescription }
            return
        }
        guard let url = create(m, name: (asset.name as NSString).deletingPathExtension) else { return }
        do {
            let store = ProjectStore.shared
            switch m {
            case .photo:
                var f = try store.load(PhotoProject.self, from: url)
                f.payload.source = try store.importMedia(file, into: url)
                try store.write(f, to: url)
            case .raster:
                var f = try store.load(RasterProject.self, from: url)
                let rel = try store.importMedia(file, into: url)
                if let src = CGImageSourceCreateWithURL(store.resolve(rel, in: url) as CFURL, nil),
                   let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
                    let s = min(1, 8000.0 / Double(max(w, h)))
                    f.payload.width = Int(Double(w) * s)
                    f.payload.height = Int(Double(h) * s)
                }
                f.payload.layers = [RasterLayer(name: asset.name, content: .image(rel))]
                try store.write(f, to: url)
            case .vector:
                let (doc, _) = try SVG.parse(Data(contentsOf: file))
                var f = try store.load(VectorProject.self, from: url)
                f.payload = doc
                try store.write(f, to: url)
            default:
                break // the editor's own import adds media (video/audio need probing)
            }
            module = m
            path = NavigationPath()
            path.append(EditorRoute.project(url, m, pendingImport: [.video, .audio].contains(m) ? file : nil))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum EditorRoute: Hashable {
    case project(URL, StudioModule, pendingImport: URL?)
    case pdf(URL)
}

import ImageIO
