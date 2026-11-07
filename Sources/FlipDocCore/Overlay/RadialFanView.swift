import SwiftUI
import Combine

@MainActor
public final class RadialFanViewModel: ObservableObject {
    @Published public var currentMode: ModifierMode
    @Published public var urls: [URL]
    @Published public var hoveredIndex: Int? = nil
    @Published public var isDragSession: Bool
    @Published public var didBloom: Bool = false

    public init(urls: [URL], mode: ModifierMode, isDragSession: Bool) {
        self.urls = urls
        self.currentMode = mode
        self.isDragSession = isDragSession
    }

    public var options: [FanOption] {
        FileCategory.options(for: urls, mode: currentMode)
    }

    public var hoveredOption: FanOption? {
        guard let idx = hoveredIndex, idx >= 0, idx < options.count else { return nil }
        return options[idx]
    }

    public var idleBadgeText: String {
        if urls.count > 1 {
            return "\(urls.count) FILES"
        }
        return currentMode.wheelTitle
    }
}

public struct RadialFanView: View {
    /// Total window canvas size. Wheel center is ALWAYS at exact `(canvasWidth/2, wheelCenterY)`.
    public static let canvasWidth: CGFloat = 340
    public static let canvasHeight: CGFloat = 360
    public static let wheelCenterX: CGFloat = 170
    public static let wheelCenterY: CGFloat = 196

    @ObservedObject public var viewModel: RadialFanViewModel
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var systemScheme

    public let onSelect: (FanOption) -> Void
    public let onClose: () -> Void
    public let onModeChange: (ModifierMode) -> Void

    public init(
        viewModel: RadialFanViewModel,
        onSelect: @escaping (FanOption) -> Void,
        onClose: @escaping () -> Void,
        onModeChange: @escaping (ModifierMode) -> Void
    ) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onClose = onClose
        self.onModeChange = onModeChange
    }

    private var useDarkGlass: Bool {
        switch prefs.wheelTheme {
        case .lightGlass: return false
        case .darkGlass: return true
        case .system: return systemScheme == .dark
        }
    }

    public var body: some View {
        let options = viewModel.options
        let isDense = options.count > 6

        ZStack {
            // Click-outside catcher when opened in non-drag (click/picker) mode
            if !viewModel.isDragSession {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onClose()
                    }
            }

            // 1. Top Floating Mode Switcher Pill (`⇧ Convert · ⌘ Tools · ⌃ Actions`)
            modePromptPill
                .position(x: Self.wheelCenterX, y: 28)
                .opacity(viewModel.didBloom ? 1.0 : 0.0)
                .offset(y: viewModel.didBloom ? 0 : 8)

            // 2. Main Radial Donut Wheel centered strictly at `(wheelCenterX, wheelCenterY)`
            ZStack {
                if options.isEmpty {
                    emptyStateCard
                } else {
                    // Frosted Glass Donut Backdrop Ring
                    DonutBackdropShape()
                        .fill(
                            useDarkGlass
                                ? Color(red: 0.14, green: 0.15, blue: 0.17).opacity(0.76)
                                : Color(red: 0.84, green: 0.87, blue: 0.89).opacity(0.50),
                            style: FillStyle(eoFill: true)
                        )
                        .background(
                            DonutBackdropShape()
                                .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    useDarkGlass ? Color.white.opacity(0.16) : Color.white.opacity(0.65),
                                    lineWidth: 1.0
                                )
                                .frame(
                                    width: PetalGeometry.backdropRadius * 2,
                                    height: PetalGeometry.backdropRadius * 2
                                )
                        )
                        .shadow(color: Color.black.opacity(useDarkGlass ? 0.42 : 0.16), radius: 18, x: 0, y: 8)

                    // Individual Curved Petals
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        let isHighlighted = (viewModel.hoveredIndex == index)
                        petalView(option: option, index: index, count: options.count, isHighlighted: isHighlighted, isDense: isDense)
                    }

                    // Center Frosted Glass Pill (`FanCenterLabelView`)
                    centerLabelPill
                }
            }
            .frame(width: PetalGeometry.wheelDiameter, height: PetalGeometry.wheelDiameter)
            .scaleEffect(viewModel.didBloom ? 1.0 : 0.52)
            .opacity(viewModel.didBloom ? 1.0 : 0.0)
            .position(x: Self.wheelCenterX, y: Self.wheelCenterY)

            // 3. Bottom Subtle Hint Caption (when hovered option is active)
            if let hovered = viewModel.hoveredOption {
                Text(viewModel.isDragSession ? "Release to \(hovered.label.lowercased())" : hovered.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(useDarkGlass ? Color.white.opacity(0.92) : Color(red: 0.22, green: 0.25, blue: 0.23))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(useDarkGlass ? Color(red: 0.14, green: 0.15, blue: 0.16).opacity(0.90) : Color.white.opacity(0.88))
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    )
                    .position(x: Self.wheelCenterX, y: Self.canvasHeight - 16)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.canvasWidth, height: Self.canvasHeight)
        .onAppear {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                viewModel.didBloom = true
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func petalView(
        option: FanOption,
        index: Int,
        count: Int,
        isHighlighted: Bool,
        isDense: Bool
    ) -> some View {
        let shape = PetalShape(index: index, count: count)
        let labelOffset = PetalGeometry.labelPosition(index: index, count: count)

        let normalGradient = LinearGradient(
            colors: useDarkGlass
                ? [Color(red: 0.22, green: 0.24, blue: 0.26).opacity(0.88), Color(red: 0.17, green: 0.18, blue: 0.20).opacity(0.82)]
                : [Color.white.opacity(0.86), Color(red: 0.95, green: 0.965, blue: 0.97).opacity(0.76)],
            startPoint: .top,
            endPoint: .bottom
        )
        let highlightGradient = LinearGradient(
            colors: [
                FlipDocTheme.orange,
                Color(red: 0.96, green: 0.29, blue: 0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let strokeColor: Color = isHighlighted
            ? Color(red: 0.78, green: 0.26, blue: 0.05).opacity(0.55)
            : (useDarkGlass ? Color.white.opacity(0.13) : Color(red: 0.36, green: 0.40, blue: 0.40).opacity(0.22))
        let shadowColor: Color = isHighlighted ? FlipDocTheme.orange.opacity(0.32) : Color.black.opacity(0.05)
        let primaryLabelFg: Color = isHighlighted ? Color.white : (useDarkGlass ? Color.white : Color.black.opacity(0.90))
        let subLabelFg: Color = isHighlighted ? Color.white : (useDarkGlass ? Color.white.opacity(0.86) : Color.black.opacity(0.82))

        ZStack {
            shape
                .fill(isHighlighted ? highlightGradient : normalGradient)
                .overlay(
                    shape.stroke(strokeColor, lineWidth: 0.85)
                )
                .shadow(
                    color: shadowColor,
                    radius: isHighlighted ? 8 : 2,
                    x: 0,
                    y: isHighlighted ? 3 : 1
                )

            // Petal Label / Icon positioned at polar centroid
            Group {
                if option.showsPetalIcon {
                    VStack(spacing: 3) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: isDense ? 14 : 16, weight: .semibold))
                            .foregroundStyle(primaryLabelFg)
                        Text(option.wheelTitle)
                            .font(.system(size: isDense ? 8.0 : 8.8, weight: .bold, design: .rounded))
                            .tracking(0.2)
                            .foregroundStyle(subLabelFg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: 64)
                } else {
                    Text(option.wheelTitle)
                        .font(.system(size: isDense ? 12.0 : 13.5, weight: .semibold, design: .rounded))
                        .tracking(0.35)
                        .foregroundStyle(primaryLabelFg)
                }
            }
            .offset(x: labelOffset.x, y: labelOffset.y)
            .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.10), value: isHighlighted)
    }

    private var centerLabelPill: some View {
        let activeOption = viewModel.hoveredOption
        let text: String = activeOption?.wheelTitle ?? viewModel.idleBadgeText
        let isCompact: Bool = (activeOption?.showsPetalIcon == true) || text.count > 6
        let fontSize: CGFloat = isCompact ? 9.5 : 11.5
        let fgColor: Color = activeOption != nil
            ? FlipDocTheme.warmOrange
            : (useDarkGlass ? Color.white.opacity(0.85) : Color.black.opacity(0.75))
        let bgColor: Color = useDarkGlass
            ? Color(red: 0.18, green: 0.19, blue: 0.21).opacity(0.90)
            : Color.white.opacity(0.84)
        let strokeColor: Color = useDarkGlass
            ? Color.white.opacity(0.18)
            : Color.white.opacity(0.85)

        return Button(action: {
            if !viewModel.isDragSession {
                onClose()
            }
        }) {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .tracking(0.3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(fgColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minWidth: 68, maxWidth: 78, minHeight: 32)
                .background(
                    Capsule()
                        .fill(bgColor)
                        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(strokeColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var modePromptPill: some View {
        let pillBg: Color = useDarkGlass
            ? Color(red: 0.14, green: 0.15, blue: 0.17).opacity(0.88)
            : Color.white.opacity(0.86)
        let pillStroke: Color = useDarkGlass
            ? Color.white.opacity(0.15)
            : Color.white.opacity(0.75)

        return HStack(spacing: 10) {
            ForEach(ModifierMode.allCases, id: \.rawValue) { mode in
                modeItemButton(for: mode)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(pillBg)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(pillStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private func modeItemButton(for mode: ModifierMode) -> some View {
        let selected: Bool = (viewModel.currentMode == mode)
        let keyBg: Color = selected
            ? FlipDocTheme.orange
            : (useDarkGlass ? Color.white.opacity(0.14) : Color(red: 0.96, green: 0.97, blue: 0.95))
        let keyStroke: Color = selected ? FlipDocTheme.orange : Color.gray.opacity(0.28)
        let keyFg: Color = selected
            ? Color.white
            : (useDarkGlass ? Color.white.opacity(0.9) : Color(red: 0.31, green: 0.35, blue: 0.31))
        let titleFg: Color = selected ? (useDarkGlass ? Color.white : Color.black) : Color.secondary

        return Button(action: {
            onModeChange(mode)
        }) {
            HStack(spacing: 4) {
                Text(mode.keySymbol)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(keyBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(keyStroke, lineWidth: 0.8)
                    )
                    .foregroundStyle(keyFg)

                Text(mode.shortTitle)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(titleFg)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyStateCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FlipDocTheme.orange)
            Text("No \(viewModel.currentMode.shortTitle.lowercased()) for this file type.")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            Text("Tap ⇧ Shift, ⌘ Command, or ⌃ Control to switch wheels.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 236)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(useDarkGlass ? Color(red: 0.15, green: 0.16, blue: 0.18).opacity(0.95) : Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.gray.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }
}
