import Foundation

/// The editors of the suite. The raw value is stored in project files: never rename a case.
public enum StudioModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo, raster, vector, paint, video, motion, animation, audio, layout, pdf, assets

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .photo: "Sviluppo foto"
        case .raster: "Fotoritocco"
        case .vector: "Vettoriale"
        case .paint: "Pittura"
        case .video: "Montaggio video"
        case .motion: "Motion"
        case .animation: "Animazione 2D"
        case .audio: "Audio"
        case .layout: "Impaginazione"
        case .pdf: "PDF"
        case .assets: "Libreria asset"
        }
    }

    public var subtitle: String {
        switch self {
        case .photo: "RAW e sviluppo non distruttivo"
        case .raster: "Livelli, fusione e filtri"
        case .vector: "Tracciati Bézier, forme, SVG"
        case .paint: "Pennelli con pressione e inclinazione"
        case .video: "Timeline multitraccia"
        case .motion: "Composizioni e keyframe"
        case .animation: "Fotogrammi, onion skin"
        case .audio: "Waveform, effetti, WAV"
        case .layout: "Documenti multipagina, PDF"
        case .pdf: "Lettura, annotazioni, pagine"
        case .assets: "Catalogo, tag e ricerca"
        }
    }

    public var systemImage: String {
        switch self {
        case .photo: "camera.aperture"
        case .raster: "square.3.layers.3d"
        case .vector: "point.topleft.down.to.point.bottomright.curvepath"
        case .paint: "paintbrush.pointed"
        case .video: "film.stack"
        case .motion: "sparkles.rectangle.stack"
        case .animation: "figure.run"
        case .audio: "waveform"
        case .layout: "doc.richtext"
        case .pdf: "doc.text.magnifyingglass"
        case .assets: "photo.on.rectangle.angled"
        }
    }

    /// Whether the module stores its work as a Studio project (`.studio` package).
    public var hasProjects: Bool { self != .assets && self != .pdf }
}
