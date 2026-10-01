import LingGanGuCore
import SwiftUI

struct BubbleDetailPanelView: View {
    @ObservedObject var appState: IdeaAppState
    let openWorkbench: () -> Void

    var body: some View {
        Group {
            if let idea = appState.bubbleDetailIdea {
                detail(for: idea)
            } else {
                Color.clear
            }
        }
        .frame(width: 320, height: 240)
        .background(.ultraThickMaterial)
        .background(AppPalette.canvas.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            appState.bubbleDetailIdea.map { "当前灵感：\($0.rawText)" } ?? "灵感详情"
        )
    }

    private func detail(for idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(idea.status == .testing ? AppPalette.amber : AppPalette.coral)
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 1) {
                    Text("灵感详情")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(idea.status.localizedName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppPalette.secondaryText)
                }

                Spacer()

                Button(action: appState.dismissBubbleDetail) {
                    Label("关闭", systemImage: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(
                            AppPalette.primaryText.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.primaryText)
                .accessibilityHint("关闭详情并释放当前气泡")
            }

            ScrollView {
                Text(idea.rawText)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: idea.tags.isEmpty ? 82 : 64)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.72))
            }

            if !idea.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(idea.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 7)
                                .frame(height: 21)
                                .background(
                                    AppPalette.lavender.opacity(0.18),
                                    in: Capsule()
                                )
                        }
                    }
                }
                .frame(height: 21)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 7
            ) {
                DetailActionButton(
                    title: "完成",
                    symbol: "checkmark",
                    tint: AppPalette.moss
                ) {
                    Task { await appState.completeBubbleIdea(idea.id) }
                }
                DetailActionButton(
                    title: "抛弃",
                    symbol: "trash",
                    tint: AppPalette.coral
                ) {
                    Task { await appState.discardBubbleIdea(idea.id) }
                }
                DetailActionButton(
                    title: idea.status == .testing ? "取消进行中" : "开始行动",
                    symbol: idea.status == .testing ? "bolt.slash.fill" : "bolt.fill",
                    tint: AppPalette.amber,
                    selected: idea.status == .testing
                ) {
                    Task { await appState.startCompletingBubbleIdea(idea.id) }
                }
                DetailActionButton(
                    title: "与 AI 讨论",
                    symbol: "message",
                    tint: AppPalette.lavender
                ) {
                    appState.prepareAIDiscussion(for: idea.id)
                    openWorkbench()
                }
            }
        }
        .padding(14)
    }
}

private struct DetailActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 31)
                .foregroundStyle(selected ? Color.white : AppPalette.primaryText)
                .background(
                    selected ? tint : tint.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
    }
}
