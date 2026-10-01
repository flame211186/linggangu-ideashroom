import LingGanGuCore
import SwiftUI

struct AISettingsView: View {
    @ObservedObject var appState: IdeaAppState
    let showGuide: () -> Void
    let close: () -> Void

    @State private var baseURL = AISettings.defaultBaseURL
    @State private var model = ""
    @State private var apiKey = ""
    @State private var timeoutSeconds = 45.0
    @State private var automaticAnnotationEnabled = false
    @State private var backfillChoice: AnnotationBackfillChoice = .futureOnly
    @State private var showBackfillChoice = false
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 设置")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("OpenAI-compatible · 配置保存在本机")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer()
                Button(action: showGuide) {
                    Label("配置指南", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)
                Button("关闭", action: close)
                    .buttonStyle(.bordered)
            }
            .padding(20)

            Divider().opacity(0.5)

            Form {
                Section("接口") {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("模型名称（必填）", text: $model)
                        .textFieldStyle(.roundedBorder)
                    SecureField(
                        appState.keychainStatusUnavailable
                            ? "钥匙串状态未确认；使用 AI 时会请求授权"
                            : appState.hasStoredAPIKey
                            ? "API Key 已保存在 Keychain；留空表示不更换"
                            : "API Key",
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    Text("远程地址必须使用 HTTPS；localhost、127.0.0.1 和 ::1 可不填密钥。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppPalette.secondaryText)
                }

                Section("行为") {
                    HStack {
                        Text("请求超时")
                        Spacer()
                        Stepper(
                            "\(Int(timeoutSeconds)) 秒",
                            value: $timeoutSeconds,
                            in: 5...180,
                            step: 5
                        )
                    }

                    Toggle(
                        "自动整理新灵感",
                        isOn: Binding(
                            get: { automaticAnnotationEnabled },
                            set: { newValue in
                                automaticAnnotationEnabled = newValue
                                if newValue {
                                    showBackfillChoice = true
                                }
                            }
                        )
                    )
                    Text("默认关闭。开启后，本地记录会先保存，再在后台逐条生成标题、主题和标签建议。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                if appState.hasStoredAPIKey || appState.keychainStatusUnavailable {
                    Button("删除 API Key", role: .destructive) {
                        Task { await appState.deleteStoredAPIKey() }
                    }
                }

                Spacer()

                Button {
                    appState.testAIConnection()
                } label: {
                    if appState.isTestingAIConnection {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测试连接")
                    }
                }
                .disabled(appState.isTestingAIConnection || isSaving || hasUnsavedChanges)
                .help("先保存设置再测试；测试请求可能消耗少量 token")

                Button("保存设置") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.moss)
                .disabled(isSaving)
            }
            .padding(20)
            Text(appState.aiError ?? (hasUnsavedChanges ? "设置尚未保存，请先保存后测试连接。" : (appState.activityMessage ?? "先保存设置，再测试连接。")))
                .font(.system(size: 11))
                .foregroundStyle(appState.aiError == nil ? AppPalette.secondaryText : .red)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(width: 520, height: 500)
        .background(AppPalette.canvas)
        .foregroundStyle(AppPalette.primaryText)
        .onAppear(perform: synchronizeDraft)
        .confirmationDialog(
            "开启后如何处理已有灵感？",
            isPresented: $showBackfillChoice,
            titleVisibility: .visible
        ) {
            Button("只处理以后新增") {
                backfillChoice = .futureOnly
            }
            Button("整理最近 7 天尚未整理的灵感") {
                backfillChoice = .recentSevenDays
            }
            Button("整理全部尚未整理的活跃灵感") {
                backfillChoice = .allActive
            }
            Button("取消开启", role: .cancel) {
                automaticAnnotationEnabled = false
            }
        } message: {
            Text("批量整理会把所选灵感发送到当前 API 服务，并可能产生费用。")
        }
    }

    private func synchronizeDraft() {
        let settings = appState.aiSettings
        baseURL = settings.baseURLString
        model = settings.model
        timeoutSeconds = settings.timeoutSeconds
        automaticAnnotationEnabled = settings.automaticAnnotationEnabled
    }

    private var hasUnsavedChanges: Bool {
        baseURL != appState.aiSettings.baseURLString || model != appState.aiSettings.model
            || timeoutSeconds != appState.aiSettings.timeoutSeconds
            || automaticAnnotationEnabled != appState.aiSettings.automaticAnnotationEnabled
            || !apiKey.isEmpty
    }

    private func save() {
        isSaving = true
        let draft = AISettings(
            baseURLString: baseURL,
            model: model,
            timeoutSeconds: timeoutSeconds,
            automaticAnnotationEnabled: automaticAnnotationEnabled,
            automaticAnnotationEnabledAt: appState.aiSettings.automaticAnnotationEnabledAt,
            privacyConsentHost: appState.aiSettings.privacyConsentHost
        )
        Task {
            let saved = await appState.saveAISettings(
                draft,
                apiKey: apiKey,
                backfillChoice: backfillChoice
            )
            isSaving = false
            if saved {
                apiKey = ""
            }
        }
    }
}
