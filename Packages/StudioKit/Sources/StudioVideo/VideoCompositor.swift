import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// One video layer of a composition segment.
struct LayerSpec: @unchecked Sendable {
    let trackID: CMPersistentTrackID
    let clip: Clip
    let orientation: CGImagePropertyOrientation
}

/// Instruction for one time segment: which source tracks are visible and how to draw them.
final class StudioInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let layers: [LayerSpec]
    let titles: [TitleClip]
    let renderSize: CGSize

    init(timeRange: CMTimeRange, layers: [LayerSpec], titles: [TitleClip], renderSize: CGSize) {
        self.timeRange = timeRange
        self.layers = layers
        self.titles = titles
        self.renderSize = renderSize
        requiredSourceTrackIDs = layers.isEmpty ? nil : layers.map { NSNumber(value: $0.trackID) }
    }
}

/// Custom compositor: Core Image per frame (transform, keyframes, colour, effects, opacity, titles).
/// Used both by the preview player and by the exporter, so they render identically.
final class StudioVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let bgra: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    let sourcePixelBufferAttributes: [String: any Sendable]? = StudioVideoCompositor.bgra
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = StudioVideoCompositor.bgra

    private let queue = DispatchQueue(label: "studio.video.compositor", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private let lock = NSLock()
    private var cancelled = false
    private var titleCache: [String: CIImage] = [:]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            lock.lock()
            let skip = cancelled
            lock.unlock()
            if skip {
                request.finishCancelledRequest()
                return
            }
            autoreleasepool {
                guard let ins = request.videoCompositionInstruction as? StudioInstruction,
                      let out = request.renderContext.newPixelBuffer()
                else {
                    request.finish(with: NSError(domain: "StudioVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "istruzione non valida"]))
                    return
                }
                let t = request.compositionTime.seconds
                let frame = compose(ins, at: t) { request.sourceFrame(byTrackID: $0) }
                context.render(frame, to: out, bounds: CGRect(origin: .zero, size: ins.renderSize), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                request.finish(withComposedVideoFrame: out)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock()
        cancelled = true
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            cancelled = false
            lock.unlock()
        }
    }

    func compose(_ ins: StudioInstruction, at t: Double, source: (CMPersistentTrackID) -> CVPixelBuffer?) -> CIImage {
        let rect = CGRect(origin: .zero, size: ins.renderSize)
        var image = CIImage(color: .black).cropped(to: rect)
        for layer in ins.layers {
            guard let px = source(layer.trackID) else { continue }
            let src = CIImage(cvPixelBuffer: px).oriented(layer.orientation)
            let drawn = Self.draw(src, clip: layer.clip, at: t, in: rect)
            image = drawn.composited(over: image)
        }
        for title in ins.titles {
            let a = title.opacity(at: t)
            guard a > 0, let img = titleImage(title, renderSize: ins.renderSize) else { continue }
            let ext = img.extent
            let cx = title.x * rect.width, cy = (1 - title.y) * rect.height
            let placed = img.transformed(by: CGAffineTransform(translationX: cx - ext.width / 2, y: cy - ext.height / 2))
            image = Self.withOpacity(placed, a).composited(over: image)
        }
        return image.cropped(to: rect)
    }

    static func draw(_ src: CIImage, clip: Clip, at t: Double, in rect: CGRect) -> CIImage {
        var img = src.transformed(by: CGAffineTransform(translationX: -src.extent.minX, y: -src.extent.minY))
        let tr = clip.transform(at: t)
        let fit = min(rect.width / max(img.extent.width, 1), rect.height / max(img.extent.height, 1)) * tr.scale
        let w = img.extent.width, h = img.extent.height
        var m = CGAffineTransform(translationX: -w / 2, y: -h / 2)
        m = m.concatenating(CGAffineTransform(scaleX: fit, y: fit))
        m = m.concatenating(CGAffineTransform(rotationAngle: -tr.rotation * .pi / 180))
        m = m.concatenating(CGAffineTransform(translationX: rect.midX + tr.x * rect.width, y: rect.midY - tr.y * rect.height))
        img = img.transformed(by: m)

        if !clip.color.isIdentity {
            let cc = CIFilter.colorControls()
            cc.inputImage = img
            cc.brightness = Float(clip.color.brightness)
            cc.contrast = Float(clip.color.contrast)
            cc.saturation = Float(clip.color.saturation)
            img = cc.outputImage ?? img
            if clip.color.temperature != 6500 {
                let tt = CIFilter.temperatureAndTint()
                tt.inputImage = img
                tt.neutral = CIVector(x: 6500, y: 0)
                tt.targetNeutral = CIVector(x: clip.color.temperature, y: 0)
                img = tt.outputImage ?? img
            }
        }
        img = applyEffect(clip.effect, img)
        let opacity = tr.opacity * clip.fadeFactor(at: t)
        return withOpacity(img, opacity)
    }

    static func applyEffect(_ e: ClipEffect, _ img: CIImage) -> CIImage {
        let ext = img.extent
        let out: CIImage?
        switch e {
        case .none: return img
        case .mono: let f = CIFilter.photoEffectMono(); f.inputImage = img; out = f.outputImage
        case .sepia: let f = CIFilter.sepiaTone(); f.inputImage = img; f.intensity = 0.9; out = f.outputImage
        case .blur: let f = CIFilter.gaussianBlur(); f.inputImage = img.clampedToExtent(); f.radius = 12; out = f.outputImage?.cropped(to: ext)
        case .sharpen: let f = CIFilter.sharpenLuminance(); f.inputImage = img; f.sharpness = 0.8; out = f.outputImage
        case .vignette: let f = CIFilter.vignette(); f.inputImage = img; f.intensity = 1; f.radius = 2; out = f.outputImage
        case .invert: let f = CIFilter.colorInvert(); f.inputImage = img; out = f.outputImage
        }
        return out ?? img
    }

    static func withOpacity(_ img: CIImage, _ a: Double) -> CIImage {
        guard a < 0.999 else { return img }
        let f = CIFilter.colorMatrix()
        f.inputImage = img
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(max(0, a)))
        return f.outputImage ?? img
    }

    private func titleImage(_ title: TitleClip, renderSize: CGSize) -> CIImage? {
        let key = "\(title.text)|\(title.fontSize)|\(title.color)|\(title.background)|\(renderSize)"
        if let c = titleCache[key] { return c }
        let img = Self.renderTitle(title, maxWidth: renderSize.width * 0.9)
        if titleCache.count > 64 { titleCache.removeAll() }
        titleCache[key] = img
        return img
    }

    static func renderTitle(_ title: TitleClip, maxWidth: CGFloat) -> CIImage? {
        let font = UIFont.systemFont(ofSize: title.fontSize, weight: title.isSubtitle ? .medium : .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: title.color.uiColor, .paragraphStyle: para]
        let str = NSAttributedString(string: title.text, attributes: attrs)
        let bounds = str.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).integral
        let pad = title.fontSize * 0.35
        let size = CGSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
        guard size.width > 1, size.height > 1 else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let ui = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            if title.background.a > 0 {
                title.background.uiColor.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: pad).fill()
            }
            str.draw(with: CGRect(x: pad, y: pad, width: bounds.width, height: bounds.height), options: [.usesLineFragmentOrigin], context: nil)
            _ = ctx
        }
        guard let cg = ui.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }
}

extension CGImagePropertyOrientation {
    /// Orientation that displays a track whose `preferredTransform` is `t` upright.
    init(_ t: CGAffineTransform) {
        let angle = atan2(t.b, t.a) * 180 / .pi
        switch Int(angle.rounded()) {
        case 90: self = .right
        case -90: self = .left
        case 180, -180: self = .down
        default: self = .up
        }
    }
}
