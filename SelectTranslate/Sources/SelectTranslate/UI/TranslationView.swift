import SwiftUI

struct TranslationPanelActions {
    var close: () -> Void
    var openSettings: () -> Void
    var downloadLanguages: (Language, Language) -> Void
    var contentHeightChanged: (CGFloat) -> Void
}

/// 翻译面板的内容
struct TranslationView: View {
    static let width: CGFloat = 440
    static let headerHeight: CGFloat = 40

    @Bindable var model: TranslationViewModel
    let actions: TranslationPanelActions
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        actions.contentHeightChanged(height + Self.headerHeight + 1)
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.width)
        .onChange(of: model.focusRequest) { inputFocused = true }
    }

    // MARK: - 顶栏：语言选择、固定、关闭

    private var header: some View {
        HStack(spacing: 2) {
            Menu {
                Picker("原文语言", selection: Binding(get: { model.sourceOverride }, set: { model.setSource($0) })) {
                    Text(model.detectedLanguage.map { "自动检测（\($0.name)）" } ?? "自动检测").tag(Language?.none)
                    Divider()
                    ForEach(Language.all) { Text($0.name).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(model.sourceLanguage?.name ?? "自动检测")
            }
            .help("原文语言")

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            Menu {
                Picker("译文语言", selection: Binding(get: { model.targetLanguage }, set: { model.setTarget($0) })) {
                    ForEach(Language.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(model.targetLanguage.name)
            }
            .help("译文语言")

            Spacer(minLength: 8)

            IconButton(systemImage: model.isPinned ? "pin.fill" : "pin",
                       help: model.isPinned ? "取消固定" : "固定窗口（点击外部不关闭）") {
                model.isPinned.toggle()
            }
            IconButton(systemImage: "xmark", help: "关闭（Esc）", action: actions.close)
                .keyboardShortcut(.cancelAction)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: Self.headerHeight)
        .background {
            // 顶栏空白处可以拖动窗口
            Color.clear
                .contentShape(.rect)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
    }

    // MARK: - 原文和各引擎结果

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            sourceInput
            ForEach(model.results) { result in
                EngineResultCard(result: result, targetLanguage: model.targetLanguage, actions: actions)
            }
            if let entry = model.dictionaryEntry {
                DictionaryCard(entry: entry)
            }
            if model.results.isEmpty, model.dictionaryEntry == nil, !model.sourceText.isBlank {
                Text("没有启用任何翻译引擎，可以在设置中开启。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var sourceInput: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("输入要翻译的文字，按 ↩ 翻译", text: $model.sourceText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { model.translate() }
                .onChange(of: model.sourceText) {
                    if inputFocused { model.scheduleTranslate() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            if !model.sourceText.isBlank {
                HStack(spacing: 0) {
                    IconButton(systemImage: "speaker.wave.2", help: "朗读原文") {
                        let language = model.sourceLanguage ?? .english
                        Speaker.shared.toggle(model.sourceText, voiceLanguage: language.speechCode)
                    }
                    CopyButton(text: model.sourceText)
                }
            }
        }
        .padding(.leading, 4)
    }
}

/// 单个翻译引擎的结果
private struct EngineResultCard: View {
    let result: EngineResult
    let targetLanguage: Language
    let actions: TranslationPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: result.kind.symbol)
                Text(result.kind.title)
                if result.isBusy {
                    ProgressView().controlSize(.mini)
                }
                Spacer(minLength: 0)
                if case .finished(let text) = result.state {
                    IconButton(systemImage: "speaker.wave.2", help: "朗读译文") {
                        Speaker.shared.toggle(text, voiceLanguage: targetLanguage.speechCode)
                    }
                    CopyButton(text: text)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: 22)

            switch result.state {
            case .loading:
                Text("翻译中…")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            case .streaming(let text), .finished(let text):
                Text(Self.render(text))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let failure):
                FailureView(failure: failure, actions: actions)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
    }

    /// Claude 的词典式回复里可能有 **加粗** 等行内 Markdown
    private static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct FailureView: View {
    let failure: TranslationFailure
    let actions: TranslationPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(failure.description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch failure {
            case .needsLanguageDownload(let source, let target):
                Button("下载语言包…") { actions.downloadLanguages(source, target) }
                    .controlSize(.small)
            case .missingAPIKey:
                Button("打开设置") { actions.openSettings() }
                    .controlSize(.small)
            default:
                EmptyView()
            }
        }
    }
}

/// 系统词典释义
private struct DictionaryCard: View {
    let entry: DictionaryEntry
    @State private var expanded = false

    private static let collapsedLineLimit = 8

    private var visibleLines: [DictionaryEntry.Line] {
        expanded ? entry.lines : Array(entry.lines.filter { $0.kind != .example }.prefix(Self.collapsedLineLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed")
                Text(entry.dictionaryName)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: 22)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.headword)
                    .font(.system(size: 16, weight: .semibold))
                    .textSelection(.enabled)
                ForEach(Array(entry.pronunciations.enumerated()), id: \.offset) { _, pronunciation in
                    Button {
                        Speaker.shared.toggle(entry.headword, voiceLanguage: pronunciation.voiceLanguage)
                    } label: {
                        HStack(spacing: 3) {
                            if !pronunciation.label.isEmpty {
                                Text(pronunciation.label).foregroundStyle(.secondary)
                            }
                            Text("/\(pronunciation.ipa)/")
                            Image(systemName: "speaker.wave.2").font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .help("朗读")
                }
            }

            if let note = entry.note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(visibleLines) { line in
                    lineView(line)
                }
            }
            .textSelection(.enabled)

            if expanded || entry.lines.count > visibleLines.count {
                Button(expanded ? "收起" : "展开全部释义和例句") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
        .onChange(of: entry) { expanded = false }
    }

    @ViewBuilder
    private func lineView(_ line: DictionaryEntry.Line) -> some View {
        switch line.kind {
        case .section:
            Text(line.text)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 4)
        case .sense:
            Text(line.text)
                .font(.system(size: 13))
        case .example:
            Text(line.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        case .plain:
            Text(line.text)
                .font(.system(size: 12).italic())
                .foregroundStyle(.secondary)
        }
    }
}

struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
                .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        IconButton(systemImage: copied ? "checkmark" : "doc.on.doc", help: "复制") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
    }
}
