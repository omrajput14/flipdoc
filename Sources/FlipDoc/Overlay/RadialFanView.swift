import SwiftUI
import Combine

@MainActor
public final class RadialFanViewModel: ObservableObject {
    @Published public var hoveredOptionId: String? = nil
    
    public init() {}
}

public struct RadialFanView: View {
    public let mode: ModifierMode
    public let category: FileCategory
    public let options: [FanOption]
    public let onSelect: (FanOption) -> Void
    
    @ObservedObject private var viewModel = RadialFanViewModel()
    
    public init(mode: ModifierMode, category: FileCategory, options: [FanOption], onSelect: @escaping (FanOption) -> Void) {
        self.mode = mode
        self.category = category
        self.options = options
        self.onSelect = onSelect
    }
    
    public var body: some View {
        ZStack {
            // Glassmorphic backdrop
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 320, height: 320)
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            // Center hub
            VStack(spacing: 4) {
                Text(mode.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text(mode.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100, height: 100)
            .background(Circle().fill(.thinMaterial))
            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            
            // Fan sectors
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let angle = angleForIndex(index, count: options.count)
                let isHovered = (viewModel.hoveredOptionId == option.id)
                
                Button(action: {
                    onSelect(option)
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isHovered ? .white : .primary)
                        Text(option.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isHovered ? .white : .secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 80)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isHovered ? Color.accentColor : Color.white.opacity(0.08))
                    )
                    .scaleEffect(isHovered ? 1.12 : 1.0)
                }
                .buttonStyle(.plain)
                .offset(
                    x: 108 * cos(angle.radians),
                    y: 108 * sin(angle.radians)
                )
                .onHover { hovering in
                    viewModel.hoveredOptionId = hovering ? option.id : nil
                }
            }
        }
        .frame(width: 340, height: 340)
    }
    
    private func angleForIndex(_ index: Int, count: Int) -> Angle {
        let step = (2.0 * .pi) / Double(max(1, count))
        let rad = -Double.pi / 2.0 + (Double(index) * step)
        return Angle(radians: rad)
    }
}
