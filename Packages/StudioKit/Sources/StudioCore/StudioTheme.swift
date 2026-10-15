import SwiftUI

/// "Studio scuro" design system: graphite surfaces, one violet accent, hairline separators.
/// Every editor and screen takes its colours and chrome from here.
public enum StudioTheme {
    /// The one accent: selection, active tool, primary action.
    public static let accent = Color(red: 0.545, green: 0.514, blue: 0.941) // #8B83F0
    /// Behind images, video and documents: the darkest surface, so the work stands out.
    public static let canvas = Color(red: 0.078, green: 0.078, blue: 0.086) // #141416
    /// Window background (home, lists).
    public static let background = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
    /// Side panels, tool rails, bars.
    public static let panel = Color(red: 0.137, green: 0.137, blue: 0.145) // #232325
    /// Cards, fields and controls on a panel.
    public static let raised = Color(red: 0.173, green: 0.173, blue: 0.184) // #2C2C2F
    public static let raisedStrong = Color(red: 0.227, green: 0.227, blue: 0.239) // #3A3A3D
    public static let hairline = Color.white.opacity(0.08)
    public static let playhead = Color(red: 1.0, green: 0.27, blue: 0.23)

    public static let cornerRadius: CGFloat = 10
    public static let cardRadius: CGFloat = 14
    public static let railWidth: CGFloat = 52
}

// MARK: - Surfaces

public extension View {
    /// A fixed-width side panel with the panel colour and a hairline towards the canvas.
    func studioPanel(width: CGFloat, edge: HorizontalEdge = .leading) -> some View {
        frame(width: width)
            .frame(maxHeight: .infinity)
            .background(StudioTheme.panel)
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                StudioTheme.hairline.frame(width: 1)
            }
    }

    /// A horizontal bar (transport, tool strip, timeline header).
    func studioBar(edge: VerticalEdge = .top) -> some View {
        background(StudioTheme.panel)
            .overlay(alignment: edge == .top ? .top : .bottom) { StudioTheme.hairline.frame(height: 1) }
    }

    /// Raised card: project tiles, grouped controls.
    func studioCard(radius: CGFloat = StudioTheme.cardRadius, selected: Bool = false) -> some View {
        background(StudioTheme.raised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? StudioTheme.accent : StudioTheme.hairline, lineWidth: selected ? 2 : 1)
            }
    }

    /// Editor chrome: navigation bar in the panel colour, always visible.
    func studioEditorChrome() -> some View {
        toolbarBackground(StudioTheme.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(StudioTheme.canvas)
    }
}

// MARK: - Tool rail

/// One tool in a vertical rail: icon only, accent fill when active, name as tooltip and for VoiceOver.
public struct ToolRailButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .background(isSelected ? StudioTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public extension View {
    /// Container style for a vertical tool rail (place ToolRailButtons in a VStack).
    func studioRail() -> some View {
        padding(.vertical, 10)
            .frame(width: StudioTheme.railWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(StudioTheme.panel)
            .overlay(alignment: .trailing) { StudioTheme.hairline.frame(width: 1) }
    }
}

/// Short separator between groups of rail buttons.
public struct RailDivider: View {
    public init() {}
    public var body: some View {
        StudioTheme.hairline.frame(width: 26, height: 1).padding(.vertical, 6)
    }
}

// MARK: - Module identity

/// Rounded tile with the module's symbol, used in the sidebar, home and project cards.
public struct ModuleIcon: View {
    let module: StudioModule
    let size: CGFloat
    let highlighted: Bool

    public init(_ module: StudioModule, size: CGFloat = 28, highlighted: Bool = false) {
        self.module = module
        self.size = size
        self.highlighted = highlighted
    }

    public var body: some View {
        Image(systemName: module.systemImage)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(highlighted ? Color.white : StudioTheme.accent)
            .frame(width: size, height: size)
            .background(highlighted ? StudioTheme.accent : StudioTheme.accent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Section title used on the home and in lists.
public struct StudioSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

public extension StudioSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
