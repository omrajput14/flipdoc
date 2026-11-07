import Foundation
import Combine
import ServiceManagement

public enum WheelVisualTheme: String, CaseIterable, Codable, Sendable {
    case lightGlass = "Light Glass"
    case darkGlass = "Dark Glass"
    case system = "System"
}

public struct ConversionRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sourceName: String
    public let outputPath: String
    public let actionSummary: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        sourceName: String,
        outputPath: String,
        actionSummary: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sourceName = sourceName
        self.outputPath = outputPath
        self.actionSummary = actionSummary
        self.timestamp = timestamp
    }

    public var outputURL: URL {
        URL(fileURLWithPath: outputPath)
    }

    public var outputName: String {
        outputURL.lastPathComponent
    }

    public var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: outputPath)
    }
}

@MainActor
public final class AppPreferences: ObservableObject {
    public static let shared = AppPreferences()

    private let defaults = UserDefaults.standard

    @Published public var wheelTheme: WheelVisualTheme {
        didSet { defaults.set(wheelTheme.rawValue, forKey: "FlipDoc.wheelTheme") }
    }

    @Published public var soundsAndHapticsEnabled: Bool {
        didSet { defaults.set(soundsAndHapticsEnabled, forKey: "FlipDoc.soundsAndHaptics") }
    }

    @Published public var dragModifiersEnabled: Bool {
        didSet {
            defaults.set(dragModifiersEnabled, forKey: "FlipDoc.enableDragModifiers")
            GlobalDragMonitor.shared.setEnabled(dragModifiersEnabled)
        }
    }

    @Published public var showDesktopDropZone: Bool {
        didSet {
            defaults.set(showDesktopDropZone, forKey: "FlipDoc.showDesktopDropZone")
            FloatingDropZoneWindow.shared.setVisible(showDesktopDropZone)
        }
    }

    @Published public var autoRevealInFinder: Bool {
        didSet { defaults.set(autoRevealInFinder, forKey: "FlipDoc.autoRevealInFinder") }
    }

    @Published public var autoFloatOutputs: Bool {
        didSet { defaults.set(autoFloatOutputs, forKey: "FlipDoc.autoFloatOutputs") }
    }

    @Published public var hasShownWelcome: Bool {
        didSet { defaults.set(hasShownWelcome, forKey: "FlipDoc.hasShownWelcomeV2") }
    }

    @Published public var imageCompressionQuality: Double {
        didSet { defaults.set(imageCompressionQuality, forKey: "FlipDoc.imageCompressionQuality") }
    }

    @Published public private(set) var recentRecords: [ConversionRecord] = []

    private init() {
        let rawTheme = defaults.string(forKey: "FlipDoc.wheelTheme") ?? WheelVisualTheme.lightGlass.rawValue
        self.wheelTheme = WheelVisualTheme(rawValue: rawTheme) ?? .lightGlass
        self.soundsAndHapticsEnabled = defaults.object(forKey: "FlipDoc.soundsAndHaptics") as? Bool ?? true
        self.dragModifiersEnabled = defaults.object(forKey: "FlipDoc.enableDragModifiers") as? Bool ?? true
        self.showDesktopDropZone = defaults.object(forKey: "FlipDoc.showDesktopDropZone") as? Bool ?? false
        self.autoRevealInFinder = defaults.object(forKey: "FlipDoc.autoRevealInFinder") as? Bool ?? false
        self.autoFloatOutputs = defaults.object(forKey: "FlipDoc.autoFloatOutputs") as? Bool ?? false
        self.hasShownWelcome = defaults.object(forKey: "FlipDoc.hasShownWelcomeV2") as? Bool ?? false
        let savedQuality = defaults.double(forKey: "FlipDoc.imageCompressionQuality")
        self.imageCompressionQuality = savedQuality > 0 ? savedQuality : 0.72

        if let data = defaults.data(forKey: "FlipDoc.recentRecords"),
           let decoded = try? JSONDecoder().decode([ConversionRecord].self, from: data) {
            self.recentRecords = decoded
        }
    }

    public func recordConversion(sourceName: String, outputURL: URL, summary: String) {
        let item = ConversionRecord(
            sourceName: sourceName,
            outputPath: outputURL.path,
            actionSummary: summary
        )
        recentRecords.removeAll { $0.outputPath == item.outputPath }
        recentRecords.insert(item, at: 0)
        if recentRecords.count > 25 {
            recentRecords = Array(recentRecords.prefix(25))
        }
        if let encoded = try? JSONEncoder().encode(recentRecords) {
            defaults.set(encoded, forKey: "FlipDoc.recentRecords")
        }
    }

    public func clearHistory() {
        recentRecords.removeAll()
        defaults.removeObject(forKey: "FlipDoc.recentRecords")
    }

    public var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                objectWillChange.send()
            } catch {
                // Ignore when running outside signed .app bundle
            }
        }
    }
}

