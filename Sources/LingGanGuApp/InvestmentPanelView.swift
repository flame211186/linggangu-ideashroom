import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LingGanGuCore

struct InvestmentPanelView<ScopeControls: View>: View {
    @ObservedObject var appState: IdeaAppState
    @ViewBuilder var scopeControls: () -> ScopeControls
    @State private var confirmEvaluation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            scopeControls().disabled(appState.isEvaluating)
            Text("只读建议 · 不联网调研 · 不自动执行或改变状态")
                .font(.system(size: 10.5))
                .foregroundStyle(AppPalette.secondaryText)
            if appState.isEvaluating {
                ProgressView(value: Double(appState.evaluationCompletedCount), total: Double(max(1, appState.evaluationTotalCount)))
                HStack {
                    Text("已处理 \(appState.evaluationCompletedCount)/\(appState.evaluationTotalCount) · 失败 \(appState.evaluationFailures.count)")
                        .font(.caption)
                    Spacer()
                    Button("停止") { appState.cancelInvestmentReview() }
                }
            } else {
                Button {
                    confirmEvaluation = true
                } label: {
                    Label("评估所选 \(appState.investmentScopeIdeas.count) 条灵感", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.coral)
                .disabled(appState.investmentScopeIdeas.isEmpty || appState.isLoading)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !appState.evaluationFailures.isEmpty {
                        DisclosureGroup("失败 \(appState.evaluationFailures.count) 条（可选中后重试）") {
                            ForEach(appState.evaluationFailures.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                                VStack(alignment: .leading) {
                                    Button(appState.ideas.first { $0.id == id }?.displayTitle ?? "灵感") {
                                        appState.revealIdea(id)
                                        appState.aiScopeKind = .current
                                    }
                                    Text(appState.evaluationFailures[id] ?? "失败").font(.caption)
                                }
                            }
                        }
                    }
                    if let result = appState.selectedEvaluation {
                        Text("已自动保存到本地 · 可随时查看历史")
                            .font(.caption).foregroundStyle(AppPalette.secondaryText)
                        HStack {
                            Button("保存报告…") { saveReport(result) }
                            Button("讨论此评估") {
                                Task { await appState.discussEvaluation(result) }
                            }
                            .disabled(!appState.canSwitchConversation || appState.isOpeningEvaluationDiscussion)
                        }
                        Menu {
                            ForEach(appState.currentEvaluationHistory) { item in
                                Button("\(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(item.verdict.localizedName)") {
                                    appState.selectEvaluation(item)
                                }
                            }
                        } label: {
                            Label("评估历史 · \(appState.currentEvaluationHistory.count) 次", systemImage: "clock.arrow.circlepath")
                        }
                        evaluation(result)
                    } else {
                        Text("尚无评估。选中灵感后主动发起；建议在正文中补充技能、时间和预算，缺少的信息会列为待验证证据。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppPalette.secondaryText)
                            .padding(.vertical, 12)
                    }
                    Divider()
                    Text("候选清单 · 每条取最新评估").font(.headline)
                    Text("按建议类别、模型自报置信度排序；置信度不是成功概率。已完成和已归档不列入。")
                        .font(.caption).foregroundStyle(AppPalette.secondaryText)
                    if appState.investmentCandidates.isEmpty {
                        Text("暂无候选，评估后会在这里显示。").font(.caption)
                    }
                    ForEach(appState.investmentCandidates) { item in
                        Button { appState.selectEvaluation(item) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appState.ideas.first { $0.id == item.ideaID }?.displayTitle ?? "来源灵感")
                                    .lineLimit(2)
                                Text(item.verdict.localizedName).font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog("开始投资视角评估？", isPresented: $confirmEvaluation, titleVisibility: .visible) {
            Button("发送并评估") { appState.requestInvestmentReview() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将向 \(appState.aiSettings.normalizedHost ?? "当前服务") 逐条发送所选的 \(appState.investmentScopeIdeas.count) 条灵感，可能产生 API 费用。不会发送归档记录，也不会修改灵感状态。")
        }
    }

    @ViewBuilder private func evaluation(_ result: Evaluation) -> some View {
        Text(result.verdict.localizedName).font(.system(size: 21, weight: .bold))
        Text("模型自报置信度 \(Int(result.confidence * 100))% · 非成功概率")
            .font(.caption).foregroundStyle(AppPalette.secondaryText)
        Text(result.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
        if let original = result.sourceRawText, original != appState.selectedIdea?.rawText {
            Text("灵感正文已修改：此结果基于旧版本，请重新评估。")
                .font(.caption).foregroundStyle(AppPalette.coral)
        }
        section("目标用户", [result.targetUser])
        section("判断依据", result.rationale)
        section("支持验证的理由", result.supportingArguments ?? ["旧版评估未记录此字段"])
        section("反方质疑", result.opposingArguments ?? result.risks)
        section("获客验证建议", [result.distributionPlan ?? "旧版评估未记录获客建议"])
        VStack(alignment: .leading, spacing: 4) {
            Text("评分 · 0—5，越高越有利").font(.headline)
            Text("痛点 \(result.scores.painSeverity) · 付费可能 \(result.scores.willingnessToPay) · 差异性 \(result.scores.differentiation)")
            Text("能力匹配 \(result.scores.founderFit) · 验证容易度 \(result.scores.validationEase)")
        }.font(.caption)
        section("风险", result.risks)
        section("缺失证据", result.missingEvidence)
        section("最小验证实验", [result.smallestExperiment])
        Button("定位来源灵感") { appState.revealIdea(result.ideaID) }
        DisclosureGroup("来源快照与版本") {
            Text(result.sourceRawText ?? "旧版评估未保存正文快照").textSelection(.enabled)
            Text("模型：\(result.model)\nPrompt：\(result.promptVersion)\n结构版本：\(result.schemaVersion ?? 1)")
                .font(.caption).textSelection(.enabled)
        }
    }

    private func saveReport(_ result: Evaluation) {
        let panel = NSSavePanel()
        panel.title = "保存投资评估报告"
        panel.nameFieldStringValue = "灵感菇评估-\(result.id.uuidString.prefix(8)).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(result.markdownReport.utf8).write(to: url, options: .atomic)
            appState.activityMessage = "评估报告已保存"
        } catch {
            appState.presentPersistenceError(error, context: "保存评估报告失败")
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 12)).textSelection(.enabled)
            }
            if lines.isEmpty { Text("无记录").font(.caption).foregroundStyle(AppPalette.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
