import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Shared building blocks for the editors' panels.

public struct PanelSection<Content: View>: View {
    let title: String
    @State private var expanded: Bool
    let content: Content

    public init(_ title: String, expanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        _expanded = State(initialValue: expanded)
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(expanded ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(expanded ? "aperta" : "chiusa")
            if expanded { content }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { StudioTheme.hairline.frame(height: 1) }
    }
}

/// A labelled slider with a value readout; double-tap the label to reset.
public struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let format: (Double) -> String
    let onEditing: (Bool) -> Void

    public init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1, defaultValue: Double = 0,
                format: @escaping (Double) -> String = { String(format: "%.0f", $0) }, onEditing: @escaping (Bool) -> Void = { _ in }) {
        self.label = label
        _value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.format = format
        self.onEditing = onEditing
    }

    /// Ranges that straddle zero (exposure, tint…) read from the centre, so the track
    /// is neutral with a centre tick instead of an accent fill from the left.
    private var bipolar: Bool { range.lowerBound < 0 && range.upperBound > 0 }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { onEditing(true); value = defaultValue; onEditing(false) }
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit().weight(value == defaultValue ? .regular : .semibold))
                    .foregroundStyle(value == defaultValue ? Color.secondary : StudioTheme.accent)
            }
            Slider(value: $value, in: range, step: step, onEditingChanged: onEditing)
                .controlSize(.mini)
                .tint(bipolar ? Color.white.opacity(0.22) : StudioTheme.accent)
                .background(alignment: .center) {
                    if bipolar {
                        GeometryReader { g in
                            let x = CGFloat((0 - range.lowerBound) / (range.upperBound - range.lowerBound)) * g.size.width
                            Capsule().fill(Color.white.opacity(0.35)).frame(width: 2, height: 8)
                                .position(x: x, y: g.size.height / 2)
                        }
                        .allowsHitTesting(false)
                    }
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
    }
}

/// Banner for recoverable errors.
public struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    public init(_ message: String, dismiss: @escaping () -> Void) {
        self.message = message
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Button("Chiudi", action: dismiss).font(.callout.weight(.semibold))
        }
        .padding(12)
        .studioCard(radius: 12)
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Progress overlay for long operations, with cancel.
public struct ProgressOverlay: View {
    let title: String
    let progress: Double?
    let cancel: (() -> Void)?

    public init(_ title: String, progress: Double? = nil, cancel: (() -> Void)? = nil) {
        self.title = title
        self.progress = progress
        self.cancel = cancel
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let progress { ProgressView(value: progress).frame(width: 220) } else { ProgressView() }
            Text(title).font(.callout)
            if let cancel { Button("Annulla", role: .cancel, action: cancel) }
        }
        .padding(24)
        .studioCard()
    }
}

/// Wraps UIActivityViewController to share or save an exported file.
public struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    public init(items: [Any]) { self.items = items }
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    public func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

public struct ExportedFile: Identifiable {
    public let id = UUID()
    public let url: URL
    public init(_ url: URL) { self.url = url }
}

public extension View {
    /// Presents the share sheet for an exported file (Save to Files, AirDrop…).
    func shareSheet(_ file: Binding<ExportedFile?>) -> some View {
        sheet(item: file) { f in ShareSheet(items: [f.url]) }
    }

    /// Undo / redo toolbar buttons with ⌘Z / ⇧⌘Z.
    func undoRedoToolbar(canUndo: Bool, canRedo: Bool, undo: @escaping () -> Void, redo: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: undo) { Label("Annulla", systemImage: "arrow.uturn.backward") }
                    .disabled(!canUndo).keyboardShortcut("z", modifiers: .command)
                Button(action: redo) { Label("Ripeti", systemImage: "arrow.uturn.forward") }
                    .disabled(!canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}

public extension Color {
    init(rgba: RGBAColor) {
        self = Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

/// Codable sRGB colour used in documents.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public static let black = RGBAColor(0, 0, 0)
    public static let white = RGBAColor(1, 1, 1)
    public static let clear = RGBAColor(0, 0, 0, 0)

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }

    public init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }

    /// `#rrggbb` (alpha omitted) for SVG.
    public var hex: String {
        String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
}

public extension Binding where Value == RGBAColor {
    var color: Binding<Color> {
        Binding<Color>(get: { Color(rgba: wrappedValue) }, set: { wrappedValue = RGBAColor($0) })
    }
}
