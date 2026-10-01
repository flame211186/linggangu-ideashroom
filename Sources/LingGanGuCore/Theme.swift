import Foundation

public struct ThemePalette: Codable, Equatable, Sendable {
    public var canvas: String
    public var glassTint: String
    public var primaryText: String
    public var secondaryText: String
    public var accent: String
    public var bubbleColors: [String]

    public init(
        canvas: String,
        glassTint: String,
        primaryText: String,
        secondaryText: String,
        accent: String,
        bubbleColors: [String]
    ) {
        self.canvas = canvas
        self.glassTint = glassTint
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accent = accent
        self.bubbleColors = bubbleColors
    }
}

public struct BubbleStyle: Codable, Equatable, Sendable {
    public var diameter: Double
    public var borderOpacity: Double
    public var highlightOpacity: Double

    public init(diameter: Double, borderOpacity: Double, highlightOpacity: Double) {
        self.diameter = diameter
        self.borderOpacity = borderOpacity
        self.highlightOpacity = highlightOpacity
    }
}

public enum MotionPreset: String, Codable, CaseIterable, Sendable {
    case still
    case gentleFloat
    case spores
}

public struct ThemeLayout: Codable, Equatable, Sendable {
    public var widgetWidth: Double
    public var widgetHeight: Double
    public var maximumVisibleBubbles: Int
    public var contentInsets: Double

    public init(
        widgetWidth: Double,
        widgetHeight: Double,
        maximumVisibleBubbles: Int,
        contentInsets: Double
    ) {
        self.widgetWidth = widgetWidth
        self.widgetHeight = widgetHeight
        self.maximumVisibleBubbles = maximumVisibleBubbles
        self.contentInsets = contentInsets
    }
}

public struct ThemeManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var displayName: String
    public var author: String
    public var version: String
    public var minimumAppVersion: String
    public var assetNames: [String]
    public var palette: ThemePalette
    public var bubbleStyle: BubbleStyle
    public var motionPreset: MotionPreset
    public var layout: ThemeLayout

    public init(
        schemaVersion: Int = 1,
        id: String,
        displayName: String,
        author: String,
        version: String,
        minimumAppVersion: String,
        assetNames: [String],
        palette: ThemePalette,
        bubbleStyle: BubbleStyle,
        motionPreset: MotionPreset,
        layout: ThemeLayout
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.author = author
        self.version = version
        self.minimumAppVersion = minimumAppVersion
        self.assetNames = assetNames
        self.palette = palette
        self.bubbleStyle = bubbleStyle
        self.motionPreset = motionPreset
        self.layout = layout
    }

    public static let glassSporeMushroom = ThemeManifest(
        id: "com.huomiao.linggangu.glass-spore",
        displayName: "玻璃孢子菇",
        author: "Huo_miao",
        version: "1.0.0",
        minimumAppVersion: "0.1.0",
        assetNames: [
            "glass-mushroom-highlight",
            "glass-grain"
        ],
        palette: ThemePalette(
            canvas: "#F5F0E6",
            glassTint: "#EEF0E4",
            primaryText: "#42563D",
            secondaryText: "#71806E",
            accent: "#71875F",
            bubbleColors: [
                "#AAB99A",
                "#E3B75A",
                "#C3ADD8",
                "#E98B6D"
            ]
        ),
        bubbleStyle: BubbleStyle(
            diameter: 42,
            borderOpacity: 0.38,
            highlightOpacity: 0.72
        ),
        motionPreset: .gentleFloat,
        layout: ThemeLayout(
            widgetWidth: 320,
            widgetHeight: 404,
            maximumVisibleBubbles: 14,
            contentInsets: 18
        )
    )
}

public enum ThemeValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchema
    case invalidIdentifier
    case invalidVersion
    case invalidAssetName(String)
    case invalidColor(String)
    case invalidLayout

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "不支持的主题格式版本"
        case .invalidIdentifier:
            "主题 ID 无效"
        case .invalidVersion:
            "主题版本无效"
        case .invalidAssetName(let name):
            "主题资源名称不安全：\(name)"
        case .invalidColor(let color):
            "主题颜色无效：\(color)"
        case .invalidLayout:
            "主题布局参数无效"
        }
    }
}

public enum ThemeValidator {
    private static let identifierPattern = #"^[a-zA-Z0-9][a-zA-Z0-9._-]{2,127}$"#
    private static let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][a-zA-Z0-9.-]+)?$"#
    private static let colorPattern = #"^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$"#

    public static func validate(_ manifest: ThemeManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw ThemeValidationError.unsupportedSchema
        }
        guard manifest.id.range(of: identifierPattern, options: .regularExpression) != nil else {
            throw ThemeValidationError.invalidIdentifier
        }
        guard manifest.version.range(of: versionPattern, options: .regularExpression) != nil,
              manifest.minimumAppVersion.range(of: versionPattern, options: .regularExpression) != nil else {
            throw ThemeValidationError.invalidVersion
        }
        for asset in manifest.assetNames {
            let hasForbiddenPath = asset.contains("/") || asset.contains("\\") || asset.contains("..")
            let hasExecutableSuffix = [
                ".app", ".bundle", ".dylib", ".so", ".sh", ".command", ".js", ".swift"
            ].contains { asset.lowercased().hasSuffix($0) }
            guard !asset.isEmpty, !hasForbiddenPath, !hasExecutableSuffix else {
                throw ThemeValidationError.invalidAssetName(asset)
            }
        }
        let colors = [
            manifest.palette.canvas,
            manifest.palette.glassTint,
            manifest.palette.primaryText,
            manifest.palette.secondaryText,
            manifest.palette.accent
        ] + manifest.palette.bubbleColors
        for color in colors where color.range(of: colorPattern, options: .regularExpression) == nil {
            throw ThemeValidationError.invalidColor(color)
        }
        guard (260...520).contains(manifest.layout.widgetWidth),
              (320...720).contains(manifest.layout.widgetHeight),
              (1...30).contains(manifest.layout.maximumVisibleBubbles),
              (0...64).contains(manifest.layout.contentInsets),
              (20...96).contains(manifest.bubbleStyle.diameter),
              (0...1).contains(manifest.bubbleStyle.borderOpacity),
              (0...1).contains(manifest.bubbleStyle.highlightOpacity) else {
            throw ThemeValidationError.invalidLayout
        }
    }
}
