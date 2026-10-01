import AppKit
import SwiftUI

enum QuickCaptureExitPolicy {
    static func hasUnsavedContent(text: String, manualTags: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !manualTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct QuickCaptureView: View {
    @ObservedObject var appState: IdeaAppState
    let save: (QuickCaptureDraft) async -> Bool
    let cancel: () -> Void

    @State private var text = ""
    @State private var manualTags = ""
    @State private var isSubmitting = false
    @State private var showsExitConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: requestExit) {
                    Label("退出", systemImage: "xmark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            AppPalette.primaryText.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.primaryText)
                .disabled(isSubmitting || appState.isSaving)
                .accessibilityLabel("退出快速记录")

                Label("收下一颗灵感孢子", systemImage: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.primaryText)

                Spacer()

                Text("\(text.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.secondaryText)
            }

            HStack(spacing: 12) {
                CaptureTextEditor(
                    text: $text,
                    placeholder: "现在脑海里闪过了什么？",
                    onSubmit: submit,
                    onCancel: requestExit
                )
                .frame(height: 68)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                }

                Button(action: submit) {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                        Text("收下")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 58)
                    .background(
                        LinearGradient(
                            colors: [AppPalette.sage, AppPalette.moss],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .shadow(color: AppPalette.moss.opacity(0.24), radius: 8, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSubmitting
                        || appState.isSaving
                )
                .opacity(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSubmitting
                        || appState.isSaving ? 0.45 : 1
                )
                .accessibilityLabel("保存想法")
            }

            HStack(spacing: 8) {
                Image(systemName: "number")
                    .foregroundStyle(AppPalette.secondaryText)
                TextField("可选标签；空格、逗号或 # 分隔。留空则从正文提取", text: $manualTags)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .disabled(isSubmitting || appState.isSaving)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("想法标签")

            HStack {
                Text("Enter 保存 · Shift+Enter 换行 · Esc 退出")
                Spacer()
                Text(isSubmitting || appState.isSaving ? "正在保存…" : "只保存在本机")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(AppPalette.secondaryText)
        }
        .padding(16)
        .frame(width: 520, height: 180)
        .background(.ultraThickMaterial)
        .background(AppPalette.canvas.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.78), lineWidth: 1)
        }
        .shadow(color: AppPalette.primaryText.opacity(0.2), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("快速记录想法")
        .overlay(alignment: .top) {
            if let error = appState.persistenceError {
                Text(error)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppPalette.coral.opacity(0.94), in: Capsule())
                    .offset(y: -12)
                }
        }
        .alert("确定退出吗？", isPresented: $showsExitConfirmation) {
            Button("返回", role: .cancel) {}
            Button("退出", role: .destructive, action: discardAndExit)
        } message: {
            Text("输入内容尚未保存，退出后将丢失。")
        }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSubmitting, !appState.isSaving else { return }
        let draft = QuickCaptureDraft(rawText: text, manualTagText: manualTags)
        isSubmitting = true
        Task {
            let didSave = await save(draft)
            if didSave {
                text = ""
                manualTags = ""
            }
            isSubmitting = false
        }
    }

    private func requestExit() {
        guard !isSubmitting, !appState.isSaving else { return }
        if QuickCaptureExitPolicy.hasUnsavedContent(
            text: text,
            manualTags: manualTags
        ) {
            showsExitConfirmation = true
        } else {
            cancel()
        }
    }

    private func discardAndExit() {
        text = ""
        manualTags = ""
        showsExitConfirmation = false
        cancel()
    }
}

private struct CaptureTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(AppPalette.primaryText)
        textView.insertionPointColor = NSColor(AppPalette.moss)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.setAccessibilityLabel("想法内容")
        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: CaptureTextEditor

        init(parent: CaptureTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    parent.onSubmit()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        placeholder.draw(
            at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}
