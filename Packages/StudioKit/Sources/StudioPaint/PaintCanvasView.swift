import StudioCore
import SwiftUI
import UIKit

/// UIKit canvas: Apple Pencil pressure/tilt via coalesced touches, finger pinch/pan for the view.
/// Each document layer is shown by its own CALayer (GPU composited; blend modes are applied on export).
final class PaintCanvasUIView: UIView {
    var onStrokeBegan: (() -> Void)?
    var onStrokeEnded: (() -> Void)?
    var onPick: ((CGPoint) -> Void)?
    var pencilOnly = false
    var eyedropper = false

    private(set) var engine = BrushEngine(brush: Brush())
    private let canvasLayer = CALayer()
    private var layerViews: [UUID: CALayer] = [:]
    private var active: BitmapLayer?
    private var activeID: UUID?
    private var canvasSize = CGSize(width: 1, height: 1)
    private var drawingTouch: UITouch?
    private var pending = CGRect.null
    private var link: CADisplayLink?

    // view transform (canvas pixels → view points)
    private var scale: CGFloat = 0.3
    private var offset: CGPoint = .zero
    private var fitted = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.18, alpha: 1)
        layer.addSublayer(canvasLayer)
        canvasLayer.masksToBounds = true
        canvasLayer.shadowOpacity = 0.4
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 2
        for g in [pinch, pan] as [UIGestureRecognizer] {
            g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            addGestureRecognizer(g)
        }
        link = CADisplayLink(target: self, selector: #selector(flush))
        link?.add(to: .main, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { link?.invalidate() }

    func configure(state: PaintDocumentState, project: PaintProject, activeLayer: UUID?) {
        canvasSize = CGSize(width: state.width, height: state.height)
        canvasLayer.bounds = CGRect(origin: .zero, size: canvasSize)
        canvasLayer.backgroundColor = project.background.cgColor
        let ids = project.layers.map(\.id)
        for (id, l) in layerViews where !ids.contains(id) { l.removeFromSuperlayer(); layerViews[id] = nil }
        for (i, info) in project.layers.enumerated() {
            let l = layerViews[info.id] ?? {
                let n = CALayer()
                n.frame = CGRect(origin: .zero, size: canvasSize)
                n.contentsGravity = .resize
                n.magnificationFilter = .linear
                canvasLayer.addSublayer(n)
                layerViews[info.id] = n
                n.contents = state.bitmap(info.id).makeImage()
                return n
            }()
            l.zPosition = CGFloat(i)
            l.opacity = Float(info.opacity)
            l.isHidden = !info.visible
        }
        activeID = activeLayer
        active = activeLayer.map { state.bitmap($0) }
        engine.brush = project.brush
        if !fitted, bounds.width > 0 { fit() }
    }

    func refreshAll(state: PaintDocumentState) {
        for (id, l) in layerViews { l.contents = state.bitmap(id).makeImage() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !fitted, bounds.width > 0 { fit() }
        applyTransform()
    }

    func fit() {
        guard canvasSize.width > 1 else { return }
        scale = min(bounds.width / canvasSize.width, bounds.height / canvasSize.height) * 0.92
        offset = .zero
        fitted = true
        applyTransform()
    }

    private func applyTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvasLayer.position = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        canvasLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    private func canvasPoint(_ p: CGPoint) -> CGPoint {
        canvasLayer.convert(p, from: layer)
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard drawingTouch == nil || drawingTouch?.type != .pencil else { return }
        cancelFingerStroke()
        scale = min(16, max(0.05, scale * g.scale))
        g.scale = 1
        applyTransform()
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        cancelFingerStroke()
        let t = g.translation(in: self)
        offset.x += t.x
        offset.y += t.y
        g.setTranslation(.zero, in: self)
        applyTransform()
    }

    private func cancelFingerStroke() {
        if let t = drawingTouch, t.type != .pencil {
            drawingTouch = nil
            engine.end()
            onStrokeEnded?()
        }
    }

    // MARK: touches

    private func sample(_ t: UITouch) -> StrokeSample {
        let p = canvasPoint(t.location(in: self))
        let pressure = t.type == .pencil && t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 1
        let alt = t.type == .pencil ? Double(t.altitudeAngle) : .pi / 2
        return StrokeSample(point: p, pressure: max(0.05, min(1, pressure)), altitude: alt)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drawingTouch == nil, let t = touches.first, event?.allTouches?.count == 1 || t.type == .pencil else { return }
        if pencilOnly && t.type != .pencil { return }
        if eyedropper {
            onPick?(canvasPoint(t.location(in: self)))
            return
        }
        guard let active else { return }
        drawingTouch = t
        onStrokeBegan?()
        pending = pending.union(engine.begin(sample(t), in: active.context))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = drawingTouch, touches.contains(t), let active else { return }
        if t.type != .pencil, (event?.allTouches?.count ?? 1) > 1 { return }
        for c in event?.coalescedTouches(for: t) ?? [t] {
            pending = pending.union(engine.move(to: sample(c), in: active.context))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = drawingTouch, touches.contains(t) else { return }
        drawingTouch = nil
        engine.end()
        flush()
        onStrokeEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    /// Pushes the active layer's pixels to its CALayer once per display frame.
    @objc private func flush() {
        guard !pending.isNull, let id = activeID, let active else { return }
        pending = .null
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerViews[id]?.contents = active.makeImage()
        CATransaction.commit()
    }
}

struct PaintCanvasRepresentable: UIViewRepresentable {
    let state: PaintDocumentState
    let project: PaintProject
    let activeLayer: UUID?
    let pencilOnly: Bool
    let eyedropper: Bool
    let revision: Int
    let onStrokeBegan: () -> Void
    let onStrokeEnded: () -> Void
    let onPick: (CGPoint) -> Void

    func makeUIView(context: Context) -> PaintCanvasUIView {
        let v = PaintCanvasUIView()
        v.configure(state: state, project: project, activeLayer: activeLayer)
        return v
    }

    func updateUIView(_ v: PaintCanvasUIView, context: Context) {
        v.onStrokeBegan = onStrokeBegan
        v.onStrokeEnded = onStrokeEnded
        v.onPick = onPick
        v.pencilOnly = pencilOnly
        v.eyedropper = eyedropper
        v.configure(state: state, project: project, activeLayer: activeLayer)
        if context.coordinator.revision != revision {
            context.coordinator.revision = revision
            v.refreshAll(state: state)
        }
    }

    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var revision = 0 }
}
