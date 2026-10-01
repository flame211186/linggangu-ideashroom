import AppKit
import SwiftUI

struct AIConfigurationGuideView: View {
    let close: () -> Void

    @State private var mode: GuideMode = .openAI

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 配置指南")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("选择你的服务类型，按顺序填写三个字段")
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer()
                Button("关闭", action: close)
                    .buttonStyle(.bordered)
            }
            .padding(22)

            Divider().opacity(0.5)

            Picker("服务类型", selection: $mode) {
                ForEach(GuideMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .openAI:
                        openAIGuide
                    case .compatible:
                        compatibleGuide
                    case .local:
                        localGuide
                    }

                    workflowCard
                    troubleshootingCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 640, height: 620)
        .background(AppPalette.canvas)
        .foregroundStyle(AppPalette.primaryText)
    }

    private var openAIGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideHeading(
                title: "OpenAI 官方接口",
                subtitle: "需要 OpenAI Platform API Key；ChatGPT 登录或订阅不能直接代替。"
            )

            GuideValueRow(label: "Base URL", value: "https://api.openai.com")
            GuideValueRow(
                label: "模型名称",
                value: "填写你的 Platform 项目可用的模型 ID"
            )
            GuideValueRow(
                label: "API Key",
                value: "在 OpenAI Platform 创建后粘贴到设置页"
            )

            HStack(spacing: 12) {
                Link(
                    "创建 API Key",
                    destination: URL(string: "https://platform.openai.com/api-keys")!
                )
                Link(
                    "查看模型目录",
                    destination: URL(string: "https://developers.openai.com/api/docs/models")!
                )
                Link(
                    "官方快速入门",
                    destination: URL(string: "https://developers.openai.com/api/docs/quickstart")!
                )
            }
            .font(.system(size: 11.5, weight: .semibold))
        }
    }

    private var compatibleGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideHeading(
                title: "第三方 OpenAI-compatible 服务",
                subtitle: "三个值都应从服务商的 API 文档或控制台复制，不能照搬 OpenAI 的模型名。"
            )

            GuideValueRow(
                label: "Base URL",
                value: "服务商给出的根地址或以 /v1 结尾的地址"
            )
            GuideValueRow(
                label: "模型名称",
                value: "服务商提供的精确模型 ID"
            )
            GuideValueRow(
                label: "API Key",
                value: "服务商控制台创建的密钥"
            )

            Text("灵感菇会自动补上 /v1/chat/completions；如果 Base URL 已含 /v1，也不会重复拼接。")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.secondaryText)
        }
    }

    private var localGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideHeading(
                title: "本地模型服务",
                subtitle: "本地服务必须启用 OpenAI-compatible Chat Completions 接口。"
            )

            GuideValueRow(
                label: "Base URL 示例",
                value: "http://127.0.0.1:11434/v1"
            )
            GuideValueRow(
                label: "模型名称",
                value: "本地服务中已经加载的精确模型 ID"
            )
            GuideValueRow(
                label: "API Key",
                value: "localhost、127.0.0.1、::1 可以留空"
            )

            Text("端口 11434 只是示例；请以你的本地服务实际监听地址为准。")
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.secondaryText)
        }
    }

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("正确操作顺序", systemImage: "list.number")
                .font(.system(size: 13, weight: .semibold))
            GuideStep(number: 1, text: "填写 Base URL、模型名称和 API Key。")
            GuideStep(number: 2, text: "点击“保存设置”；即使暂时断网也可以保存。")
            GuideStep(number: 3, text: "点击“测试连接”；这一步可能消耗少量 token。")
            GuideStep(number: 4, text: "看到连接成功后，再开启自动整理或进入 AI 工作台。")
        }
        .guideCard()
    }

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("常见错误", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 13, weight: .semibold))
            Text("401：密钥无效、被撤销或粘贴时带了多余空格。")
            Text("403：密钥或项目没有使用该模型的权限。")
            Text("404：Base URL、/v1 路径或模型名称不正确。")
            Text("429：额度不足或请求过于频繁。")
        }
        .font(.system(size: 11.5))
        .guideCard()
    }
}

private enum GuideMode: String, CaseIterable, Identifiable {
    case openAI = "OpenAI 官方"
    case compatible = "兼容服务"
    case local = "本地模型"

    var id: Self { self }
}

private struct GuideHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.secondaryText)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if value.hasPrefix("https://") || value.hasPrefix("http://") {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(AppPalette.moss.opacity(0.14), in: Circle())
            Text(text)
                .font(.system(size: 11.5))
        }
    }
}

private extension View {
    func guideCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 14))
    }
}
