import SwiftUI
import LingGanGuCore

enum AppPalette {
    static let canvas = Color(hex: 0xF5F0E6)
    static let glassTint = Color(hex: 0xEEF0E4)
    static let primaryText = Color(hex: 0x42563D)
    static let secondaryText = Color(hex: 0x71806E)
    static let moss = Color(hex: 0x71875F)
    static let mossDeep = Color(hex: 0x526847)
    static let amber = Color(hex: 0xE3B75A)
    static let coral = Color(hex: 0xE98B6D)
    static let lavender = Color(hex: 0xC3ADD8)
    static let sage = Color(hex: 0xAAB99A)

    static let bubbleColors = [sage, amber, lavender, coral]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension IdeaStatus {
    var localizedName: String {
        switch self {
        case .inbox, .clarified: "待处理"
        case .candidate: "想做"
        case .testing: "进行中"
        case .executed: "已完成"
        case .archived: "已归档"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .clarified: "tray"
        case .candidate: "diamond"
        case .testing: "flask"
        case .executed: "checkmark.circle"
        case .archived: "archivebox"
        }
    }

    var explanation: String {
        switch workflowStatus {
        case .inbox, .clarified: "先记下来，还没决定怎么处理"
        case .candidate: "值得做，但还没开始"
        case .testing: "已经开始行动"
        case .executed: "已完成这件事"
        case .archived: "暂时不做，保留记录，可恢复"
        }
    }
}
