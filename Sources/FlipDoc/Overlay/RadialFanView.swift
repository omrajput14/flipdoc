import SwiftUI
import Combine

@MainActor
public final class RadialFanViewModel: ObservableObject {
    @Published public var currentMode: ModifierMode
    @Published public var hoveredOptionId: String? = nil
    @Published public var isCenterHovered: Bool = false
    
    public init(mode: ModifierMode = .conversions) {
        self.currentMode = mode
    }
}

public struct RadialFanView: View {
    public let category: FileCategory
    public let fileName: String
    public let onSelect: (FanOption) -> Void
    public let onClose: () -> Void
    public let onModeChange: ((ModifierMode) -> Void)?

    @StateObject private var viewModel: RadialFanViewModel

    public init(
        mode: ModifierMode,
        category: FileCategory,
        fileName: String,
        onSelect: @escaping (FanOption) -> Void,
        onClose: @escaping () -> Void,
        onModeChange: ((ModifierMode) -> Void)? = nil
    ) {
        self._viewModel = StateObject(wrappedValue: RadialFanViewModel(mode: mode))
        self.category = category
        self.fileName = fileName
        self.onSelect = onSelect
        self.onClose = onClose
        self.onModeChange = onModeChange
    }

    private var options: [FanOption] {
        category.options(for: viewModel.currentMode)
    }

    public var body: some View {
        ZStack {
            // Dismiss background tap
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose()
                }

            VStack(spacing: 8) {
                // Top header: File name badge + Close button
                HStack(spacing: 8) {
                    Image(systemName: fileIcon)
                        .foregroundStyle(.tint)
                    Text(fileName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                // Mode Tabs
                HStack(spacing: 4) {
                    modeTab(.conversions, label: "⇧ Convert")
                    modeTab(.tools, label: "⌘ Tools")
                    modeTab(.actions, label: "⌃ Actions")
                }
                .padding(3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

                // Radial Fan Area
                ZStack {
                    // Glassmorphic circular backdrop
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 290, height: 290)
                        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    // Radial Options
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        let angle = angleForIndex(index, count: options.count)
                        let isHovered = (viewModel.hoveredOptionId == option.id)

                        Button(action: {
                            onSelect(option)
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: option.systemImage)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(isHovered ? .white : .primary)
                                Text(option.label)
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isHovered ? .white : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(maxWidth: 72)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(isHovered ? Color.accentColor : Color.white.opacity(0.08))
                            )
                            .scaleEffect(isHovered ? 1.14 : 1.0)
                            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
                        }
                        .buttonStyle(.plain)
                        .offset(
                            x: 96 * cos(angle.radians),
                            y: 96 * sin(angle.radians)
                        )
                        .onHover { hovering in
                            viewModel.hoveredOptionId = hovering ? option.id : nil
                        }
                    }

                    // Center Hub: Close / Dismiss trigger
                    Button(action: onClose) {
                        VStack(spacing: 3) {
                            if viewModel.isCenterHovered {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.red)
                                Text("Close")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red)
                            } else {
                                Text(viewModel.currentMode.label)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(maxWidth: 70)
                                Text("Esc to close")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 86, height: 86)
                        .background(
                            Circle()
                                .fill(viewModel.isCenterHovered ? Color.red.opacity(0.12) : Color.white.opacity(0.1))
                        )
                        .overlay(
                            Circle()
                                .stroke(viewModel.isCenterHovered ? Color.red.opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        viewModel.isCenterHovered = hovering
                    }
                }
                .frame(width: 310, height: 310)
            }
        }
        .frame(width: 380, height: 400)
    }

    private func modeTab(_ mode: ModifierMode, label: String) -> some View {
        let isSelected = (viewModel.currentMode == mode)
        return Button(action: {
            viewModel.currentMode = mode
            onModeChange?(mode)
        }) {
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func angleForIndex(_ index: Int, count: Int) -> Angle {
        let step = (2.0 * .pi) / Double(max(1, count))
        let rad = -Double.pi / 2.0 + (Double(index) * step)
        return Angle(radians: rad)
    }

    private var fileIcon: String {
        switch category {
        case .pdf: return "doc.fill"
        case .image: return "photo.fill"
        case .audio: return "waveform"
        case .video: return "film"
        case .spreadsheet: return "tablecells"
        case .document: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .unknown: return "doc"
        }
    }
}
