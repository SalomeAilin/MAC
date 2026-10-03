import SwiftUI

struct EngineSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var packState: PackState = .checking
    @State private var apiKeyDraft = ""
    @State private var isReplacingKey = false
    @State private var keyError: String?
    @State private var testState: TestState = .idle

    private enum PackState { case checking, installed, needsDownload, unsupported }
    private enum TestState: Equatable { case idle, running, success(String), failure(String) }

    /// 设置页展示最常用的语言对：第二语言 ↔ 首选语言（默认英语 ↔ 简体中文）
    private var packPair: (source: Language, target: Language) {
        (settings.secondaryLanguage, settings.primaryLanguage)
    }

    var body: some View {
        Form {
            Section {
                Toggle("启用谷歌翻译", isOn: $settings.googleEnabled)
            } header: {
                Text("谷歌翻译")
            } footer: {
                Text("联网翻译，免费，不需要 API Key，译文通常比系统自带的更通顺。选中的文字会发送给谷歌；需要能访问谷歌；使用的是谷歌网页翻译的公开接口（非官方 API），以后可能失效。")
            }

            Section {
                Toggle("启用 Apple 翻译", isOn: $settings.appleEnabled)
                if #available(macOS 26.4, *) {
                    Picker("翻译模式", selection: $settings.appleMode) {
                        ForEach(AppleTranslationMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                LabeledContent("语言包（\(packPair.source.name) ↔ \(packPair.target.name)）") {
                    packStatusView
                }
            } header: {
                Text("Apple 翻译")
            } footer: {
                Text("使用 macOS 内置的翻译模型在本机离线完成，免费，文字不会离开你的 Mac。用到其他语言时会提示下载对应语言包，也可以在「系统设置 › 通用 › 语言与地区 › 翻译语言」中管理。")
            }

            Section {
                Toggle("查英文单词时显示词典释义", isOn: $settings.dictionaryEnabled)
            } header: {
                Text("系统词典")
            } footer: {
                Text("使用「词典」App 中启用的词典（例如「牛津英汉汉英词典」），可以在词典 App 的设置里启用词典或调整顺序。")
            }

            Section {
                apiKeyRow
                if let keyError {
                    Label(keyError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                if settings.hasAnthropicAPIKey {
                    Toggle("启用 Claude 翻译", isOn: $settings.claudeEnabled)
                    Picker("模型", selection: $settings.claudeModel) {
                        ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.claudeModel.supportsEffort {
                        Picker("思考强度", selection: $settings.claudeEffort) {
                            ForEach(ClaudeEffort.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Button("测试") { runTest() }
                            .disabled(testState == .running)
                        testStateView
                    }
                }
            } header: {
                Text("Claude（可选）")
            } footer: {
                Text("没有 API Key 可以忽略这一项，上面的 Apple 翻译和系统词典已经够用。填入 Anthropic API Key 后，可以额外显示 Claude 的译文，单词和短语会给出词典式解释；按用量计费，选中的文字会发送给 Anthropic。")
            }
        }
        .formStyle(.grouped)
        .task(id: "\(packPair.source.code)-\(packPair.target.code)") {
            await refreshPackState()
        }
    }

    @ViewBuilder
    private var packStatusView: some View {
        switch packState {
        case .checking:
            ProgressView().controlSize(.small)
        case .installed:
            Label("已安装", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsDownload:
            Button("下载…") {
                LanguagePackDownloader.shared.present(source: packPair.source, target: packPair.target) {
                    Task { await refreshPackState() }
                }
            }
        case .unsupported:
            Text("不支持")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var apiKeyRow: some View {
        LabeledContent("API Key") {
            if settings.hasAnthropicAPIKey && !isReplacingKey {
                HStack {
                    Text("已保存在钥匙串")
                        .foregroundStyle(.secondary)
                    Button("更换") {
                        keyError = nil
                        isReplacingKey = true
                    }
                    Button("删除") {
                        guard settings.setAnthropicAPIKey(nil) else {
                            keyError = "无法从钥匙串删除 API Key，请重试。"
                            return
                        }
                        keyError = nil
                        settings.claudeEnabled = false
                        testState = .idle
                    }
                }
            } else {
                HStack {
                    SecureField("API Key", text: $apiKeyDraft, prompt: Text("sk-ant-…"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(saveKey)
                    Button("保存", action: saveKey)
                        .disabled(apiKeyDraft.isBlank)
                    if isReplacingKey {
                        Button("取消") {
                            keyError = nil
                            isReplacingKey = false
                            apiKeyDraft = ""
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var testStateView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .success(let text):
            Label(text, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(2)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    private func saveKey() {
        guard !apiKeyDraft.isBlank else { return }
        guard settings.setAnthropicAPIKey(apiKeyDraft) else {
            keyError = "无法把 API Key 保存到钥匙串，请重试。"
            return
        }
        keyError = nil
        apiKeyDraft = ""
        isReplacingKey = false
        settings.claudeEnabled = true
        testState = .idle
    }

    private func runTest() {
        guard let apiKey = settings.anthropicAPIKey else { return }
        let target = settings.primaryLanguage == .english ? Language.simplifiedChinese : settings.primaryLanguage
        testState = .running
        Task {
            var output = ""
            do {
                try await ClaudeTranslator.translate(
                    "Hello, nice to meet you!", from: .english, to: target,
                    model: settings.claudeModel, effort: settings.claudeEffort, apiKey: apiKey
                ) { output += $0 }
                testState = .success("连接正常：\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            } catch {
                testState = .failure((error as? TranslationFailure)?.description ?? error.localizedDescription)
            }
        }
    }

    private func refreshPackState() async {
        packState = .checking
        switch await AppleTranslator.languagePackStatus(packPair.source, packPair.target) {
        case .installed: packState = .installed
        case .supported: packState = .needsDownload
        default: packState = .unsupported
        }
    }
}
