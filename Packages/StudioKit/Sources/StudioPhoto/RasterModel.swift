import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import StudioCore
import UIKit
import UniformTypeIdentifiers

/// Layered raster compositing (the "Fotoritocco" editor): image, fill and paint layers with masks,
/// blend modes, opacity, transforms and non-destructive Core Image filters.
public struct RasterProject: ProjectPayload {
    public static let kind = StudioModule.raster
    public static let formatVersion = 1

    public var width = 3000
    public var height = 2000
    public var background = RGBAColor.white
    /// Bottom → top.
    public var layers: [RasterLayer] = []

    public init() {}
}

public enum RasterBlend: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, softLight, hardLight, darken, lighten, difference, colorDodge, colorBurn, hue, saturation, color, luminosity

    public var title: String {
        switch self {
        case .normal: "Normale"
        case .multiply: "Moltiplica"
        case .screen: "Scolora"
        case .overlay: "Sovrapponi"
        case .softLight: "Luce soffusa"
        case .hardLight: "Luce intensa"
        case .darken: "Scurisci"
        case .lighten: "Schiarisci"
        case .difference: "Differenza"
        case .colorDodge: "Colore schiarito"
        case .colorBurn: "Colore brucia"
        case .hue: "Tonalità"
        case .saturation: "Saturazione"
        case .color: "Colore"
        case .luminosity: "Luminosità"
        }
    }

    var ciFilter: String? {
        switch self {
        case .normal: nil
        case .multiply: "CIMultiplyBlendMode"
        case .screen: "CIScreenBlendMode"
        case .overlay: "CIOverlayBlendMode"
        case .softLight: "CISoftLightBlendMode"
        case .hardLight: "CIHardLightBlendMode"
        case .darken: "CIDarkenBlendMode"
        case .lighten: "CILightenBlendMode"
        case .difference: "CIDifferenceBlendMode"
        case .colorDodge: "CIColorDodgeBlendMode"
        case .colorBurn: "CIColorBurnBlendMode"
        case .hue: "CIHueBlendMode"
        case .saturation: "CISaturationBlendMode"
        case .color: "CIColorBlendMode"
        case .luminosity: "CILuminosityBlendMode"
        }
    }
}

public enum RasterFilterKind: String, Codable, CaseIterable, Sendable {
    case brightness, contrast, saturation, exposure, gaussianBlur, sharpen, noiseReduction, vignette, sepia, mono, invert, posterize, pixellate, hueShift

    public var title: String {
        switch self {
        case .brightness: "Luminosità"
        case .contrast: "Contrasto"
        case .saturation: "Saturazione"
        case .exposure: "Esposizione"
        case .gaussianBlur: "Sfocatura gaussiana"
        case .sharpen: "Maschera di contrasto"
        case .noiseReduction: "Riduzione rumore"
        case .vignette: "Vignettatura"
        case .sepia: "Seppia"
        case .mono: "Bianco e nero"
        case .invert: "Inverti"
        case .posterize: "Posterizza"
        case .pixellate: "Pixel"
        case .hueShift: "Tonalità"
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .brightness: -1 ... 1
        case .contrast, .saturation: 0 ... 2
        case .exposure: -3 ... 3
        case .gaussianBlur: 0 ... 100
        case .sharpen: 0 ... 3
        case .noiseReduction: 0 ... 0.1
        case .vignette: 0 ... 3
        case .sepia, .mono, .invert: 0 ... 1
        case .posterize: 2 ... 30
        case .pixellate: 1 ... 100
        case .hueShift: -180 ... 180
        }
    }

    public var defaultAmount: Double {
        switch self {
        case .contrast, .saturation, .sepia, .mono, .invert: 1
        case .gaussianBlur: 8
        case .sharpen: 0.8
        case .noiseReduction: 0.02
        case .vignette: 1
        case .posterize: 6
        case .pixellate: 12
        default: 0
        }
    }
}

public struct RasterFilter: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: RasterFilterKind
    public var amount: Double
    public var enabled = true
    public init(_ k: RasterFilterKind) { kind = k; amount = k.defaultAmount }
}

public enum RasterContent: Codable, Hashable, Sendable {
    /// Image file in Media (relative path).
    case image(String)
    case fill(RGBAColor)
    /// Pixels painted in the app, stored as Media/Raster/<id>.png.
    case paint
}

public struct RasterLayer: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var content: RasterContent
    public var visible = true
    public var opacity: Double = 1
    public var blend: RasterBlend = .normal
    public var x: Double = 0
    public var y: Double = 0
    public var scale: Double = 1
    public var rotation: Double = 0
    public var filters: [RasterFilter] = []
    /// Greyscale mask PNG (Media/Raster/<id>-mask.png): white shows, black hides.
    public var hasMask = false
    public var maskEnabled = true

    public init(name: String, content: RasterContent) {
        self.name = name
        self.content = content
    }

    public var paintFile: String { "Media/Raster/\(id.uuidString).png" }
    public var maskFile: String { "Media/Raster/\(id.uuidString)-mask.png" }
}

/// Core Image compositor shared by the canvas preview and the exporter.
public final class RasterCompositor: @unchecked Sendable {
    let projectURL: URL
    private var cache: [String: CIImage] = [:]
    public let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    public init(projectURL: URL) { self.projectURL = projectURL }

    public func invalidate(_ relative: String? = nil) {
        if let relative { cache[relative] = nil } else { cache.removeAll() }
    }

    func load(_ relative: String) -> CIImage? {
        if let c = cache[relative] { return c }
        let url = projectURL.appendingPathComponent(relative)
        guard let i = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        cache[relative] = i
        return i
    }

    /// Image space: CI origin bottom-left, document size width × height.
    public func compose(_ p: RasterProject, overrides: [String: CIImage] = [:]) -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: p.width, height: p.height)
        var out = CIImage(color: CIColor(cgColor: p.background.cgColor)).cropped(to: rect)
        for l in p.layers where l.visible {
            guard var img = layerImage(l, doc: p, overrides: overrides) else { continue }
            img = applyFilters(l.filters, img)
            if l.hasMask, l.maskEnabled, let m = overrides[l.maskFile] ?? load(l.maskFile) {
                let mask = m.transformed(by: CGAffineTransform(scaleX: rect.width / max(1, m.extent.width), y: rect.height / max(1, m.extent.height)))
                img = img.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
            }
            if l.opacity < 0.999 {
                img = img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: l.opacity)])
            }
            if let f = l.blend.ciFilter {
                out = img.applyingFilter(f, parameters: [kCIInputBackgroundImageKey: out]).cropped(to: rect)
            } else {
                out = img.composited(over: out).cropped(to: rect)
            }
        }
        return out
    }

    func layerImage(_ l: RasterLayer, doc p: RasterProject, overrides: [String: CIImage]) -> CIImage? {
        let rect = CGRect(x: 0, y: 0, width: p.width, height: p.height)
        switch l.content {
        case .fill(let c): return CIImage(color: CIColor(cgColor: c.cgColor)).cropped(to: rect)
        case .paint:
            return overrides[l.paintFile] ?? load(l.paintFile)
        case .image(let path):
            guard let src = load(path) else { return nil }
            let e = src.extent
            // fit inside the canvas, then the layer's own transform (y is top-down in the UI)
            let fit = min(rect.width / e.width, rect.height / e.height)
            var t = CGAffineTransform(translationX: -e.midX, y: -e.midY)
            t = t.concatenating(CGAffineTransform(scaleX: fit * l.scale, y: fit * l.scale))
            t = t.concatenating(CGAffineTransform(rotationAngle: -l.rotation * .pi / 180))
            t = t.concatenating(CGAffineTransform(translationX: rect.midX + l.x, y: rect.midY - l.y))
            return src.transformed(by: t)
        }
    }

    public func applyFilters(_ fs: [RasterFilter], _ input: CIImage) -> CIImage {
        var img = input
        let ext = input.extent
        for f in fs where f.enabled {
            switch f.kind {
            case .brightness: img = img.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: f.amount])
            case .contrast: img = img.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: f.amount])
            case .saturation: img = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: f.amount])
            case .exposure: img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: f.amount])
            case .gaussianBlur: img = img.clampedToExtent().applyingGaussianBlur(sigma: f.amount).cropped(to: ext)
            case .sharpen: img = img.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 2.5, kCIInputIntensityKey: f.amount])
            case .noiseReduction: img = img.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": f.amount, "inputSharpness": 0.4])
            case .vignette: img = img.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: f.amount, kCIInputRadiusKey: 1.5])
            case .sepia: img = img.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: f.amount])
            case .mono: img = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - f.amount])
            case .invert: if f.amount > 0.5 { img = img.applyingFilter("CIColorInvert") }
            case .posterize: img = img.applyingFilter("CIColorPosterize", parameters: ["inputLevels": f.amount])
            case .pixellate: img = img.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: f.amount, kCIInputCenterKey: CIVector(x: ext.midX, y: ext.midY)]).cropped(to: ext)
            case .hueShift: img = img.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: f.amount * .pi / 180])
            }
        }
        return img
    }

    public func render(_ p: RasterProject, maxSize: CGSize? = nil, overrides: [String: CIImage] = [:]) -> CGImage? {
        var img = compose(p, overrides: overrides)
        if let maxSize {
            let s = min(1, min(maxSize.width / CGFloat(p.width), maxSize.height / CGFloat(p.height)))
            if s < 1 { img = img.transformed(by: CGAffineTransform(scaleX: s, y: s)) }
        }
        return context.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    public func export(_ p: RasterProject, to url: URL, type: UTType, quality: Double = 0.92) throws {
        guard let cg = render(p) else { throw StudioError.engine("composizione non riuscita") }
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw StudioError.io("destinazione") }
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw StudioError.io("scrittura non riuscita") }
    }
}
