import LingGanGuCore
import AppKit
import SwiftUI

struct WidgetView: View {
    @ObservedObject var appState: IdeaAppState
    let openQuickCapture: () -> Void
    let openWorkbench: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            BubblePhysicsView(
                ideas: appState.recentIdeas,
                pinnedIdeaID: appState.bubbleDetailIdeaID,
                reduceMotion: reduceMotion,
                onSelect: selectBubble,
                onDragReleased: { _ in appState.dismissBubbleDetail() }
            )
            .frame(width: 288, height: 206)
            .offset(x: 16, y: 36)
            .accessibilityHint("点击气泡查看灵感，按住拖动，放开后自然掉落")

            mushroomAsset
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 320, height: 404)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            stemContent
        }
        .frame(width: 320, height: 404)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("灵感菇桌面组件，本周 \(appState.weeklyCount) 个想法")
    }

    private var mushroomAsset: Image {
        guard let url = AppResources.bundle.url(
            forResource: "glass-mushroom-empty",
            withExtension: "png"
        ),
        let image = NSImage(contentsOf: url) else {
            return Image(nsImage: NSImage(size: NSSize(width: 320, height: 404)))
        }
        return Image(nsImage: image)
    }

    private func selectBubble(_ ideaID: UUID) {
        guard let idea = appState.ideas.first(where: { $0.id == ideaID }) else {
            return
        }
        appState.toggleBubbleDetail(idea)
    }

    private var stemContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppPalette.moss.opacity(0.65))
                    .frame(width: 4, height: 4)
                Text("灵感菇")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(AppPalette.primaryText)
                Circle()
                    .fill(AppPalette.moss.opacity(0.65))
                    .frame(width: 4, height: 4)
            }
            .padding(.top, 244)

            Rectangle()
                .fill(AppPalette.moss.opacity(0.24))
                .frame(width: 112, height: 1)
                .padding(.top, 7)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("本周")
                    .font(.system(size: 13, weight: .medium))
                Text("\(appState.weeklyCount)")
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .monospacedDigit()
                Text("个想法")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(AppPalette.primaryText)
            .padding(.top, 7)

            HStack(spacing: 7) {
                Button(action: openWorkbench) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppPalette.coral)
                            .frame(width: 8, height: 8)
                            .shadow(color: AppPalette.coral.opacity(0.55), radius: 4)
                        Text(appState.selectedIdea?.displayTitle ?? "把刚出现的想法收进来")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppPalette.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 13)
                    .frame(width: 140, height: 32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    }
                    .shadow(color: AppPalette.primaryText.opacity(0.10), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开当前想法详情")

                Button(action: openQuickCapture) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(
                                colors: [AppPalette.sage, AppPalette.moss],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                        }
                        .shadow(color: AppPalette.primaryText.opacity(0.16), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("记录新想法")
                .accessibilityHint("快捷键 Command Shift Space")
            }
            .padding(.top, 3)
        }
        .frame(width: 320, height: 404, alignment: .top)
    }
}
