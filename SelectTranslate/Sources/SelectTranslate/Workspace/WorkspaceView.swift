import AppKit
import SwiftUI
import WebKit

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case notes = "日记与笔记", web = "网页资料", assistant = "AI 助手", network = "网络"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .notes: "book.closed"
        case .web: "globe"
        case .assistant: "sparkles"
        case .network: "network"
        }
    }
}

struct WorkspaceView: View {
    let controller: WorkspaceWindowController
    let translate: (String) -> Void
    @State private var section: WorkspaceSection? = .notes
    @State private var search = ""

    var body: some View {
        @Bindable var browser = controller.browser
        @Bindable var capture = controller.capture
        NavigationSplitView {
            List(WorkspaceSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
                    .padding(.vertical, 5)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                Text("保存在这台 Mac 上")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            switch section ?? .notes {
            case .notes: notesView
            case .web: browserView
            case .assistant: assistantView
            case .network: networkView
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { controller.notes.openToday(); section = .notes } label: { Label("今日日记", systemImage: "calendar") }
                    .disabled(controller.notes.isReadOnly)
                Button { controller.takeScreenshot() } label: { Label("区域截图", systemImage: "camera.viewfinder") }
                    .disabled(capture.isCapturing || controller.notes.isReadOnly)
                Button { SettingsWindowController.shared.show() } label: { Label("设置", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $browser.isPreviewing) { excerptPreview }
        .sheet(isPresented: $capture.isPreviewingText) { recognizedTextPreview }
        .onChange(of: controller.notes.selectedID) { _, _ in
            if capture.isCapturing { section = .notes }
        }
    }

    private var notesView: some View {
        @Bindable var notes = controller.notes
        return HSplitView {
            VStack(spacing: 12) {
                TextField("搜索笔记", text: $search).textFieldStyle(.roundedBorder).padding([.horizontal, .top])
                List(selection: $notes.selectedID) {
                    ForEach(notes.sortedNotes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.title.isEmpty ? "未命名笔记" : note.title).font(.headline).lineLimit(1)
                            Text(note.body.isEmpty ? (note.attachments.isEmpty ? "空白笔记" : "截图") : note.body)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4).tag(note.id)
                    }
                }
                Button { notes.add() } label: { Label("新建笔记", systemImage: "square.and.pencil") }
                    .buttonStyle(.bordered).disabled(notes.isReadOnly).padding(.bottom)
            }.frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
            VStack(alignment: .leading, spacing: 16) {
                if let error = notes.error { errorLabel(error) }
                if let error = controller.capture.error { errorLabel(error) }
                if let note = notes.selectedNote {
                    TextField("标题", text: Binding(get: { notes.document.notes.first { $0.id == note.id }?.title ?? "" }, set: { notes.update(id: note.id, title: $0) }))
                        .font(.title2.weight(.semibold)).textFieldStyle(.plain).disabled(notes.isReadOnly)
                        .id(note.id)
                    HStack {
                        Text(notes.hasUnsavedChanges ? "正在保存…" : "已保存在本机")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("交给 AI") {
                            controller.assistant.context = note.title + "\n\n" + note.body
                            section = .assistant
                        }.disabled(note.body.isBlank)
                        Button("翻译正文") { translate(note.body) }.disabled(note.body.isBlank)
                        Button("导出文字") { controller.exportCurrentText() }
                    }
                    TextEditor(text: Binding(get: { notes.document.notes.first { $0.id == note.id }?.body ?? "" }, set: { notes.update(id: note.id, body: $0) }))
                        .font(.body).scrollContentBackground(.hidden).disabled(notes.isReadOnly)
                        // 切页时创建独立编辑器，避免撤销记录把上一页内容写入新页。
                        .id(note.id)
                    if let source = note.sourceURL { Link("查看来源网页", destination: source).font(.caption) }
                    if !note.attachments.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(note.attachments) { attachment in
                                    VStack(alignment: .leading) {
                                        WorkspaceAttachmentView(url: notes.repository.attachmentsURL.appendingPathComponent(attachment.filename))
                                        HStack {
                                            Button("识别文字") { controller.capture.recognize(attachment, noteID: note.id, in: notes) }
                                                .disabled(controller.capture.isRecognizing)
                                            Button("在访达中显示") {
                                                NSWorkspace.shared.activateFileViewerSelecting([notes.repository.attachmentsURL.appendingPathComponent(attachment.filename)])
                                            }
                                        }.font(.caption)
                                    }
                                }
                            }
                        }.frame(height: 190)
                    }
                } else {
                    ContentUnavailableView("从一篇日记开始", systemImage: "book.closed", description: Text("写下今天的想法，或把网页摘录和截图保存在这里。"))
                }
            }.padding(24).frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var browserView: some View {
        @Bindable var browser = controller.browser
        return VStack(spacing: 12) {
            HStack {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                TextField("输入网址或搜索内容", text: $browser.address).textFieldStyle(.roundedBorder).onSubmit { browser.open() }
                Button("打开") { browser.open() }
                Button("摘录 / 翻译选中文字") { browser.previewSelection() }
            }.padding([.horizontal, .top])
            if let error = browser.error { errorLabel(error).padding(.horizontal) }
            WorkspaceWebView(webView: browser.webView)
        }
    }

    private var assistantView: some View {
        @Bindable var assistant = controller.assistant
        return VStack(alignment: .leading, spacing: 16) {
            Text("AI 助手").font(.title2.weight(.semibold))
            Text("只有点击发送，输入和附上的资料才会发送给 Anthropic。不会自动读取其他日记、截图或网络诊断。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $assistant.prompt).font(.body).frame(minHeight: 80, maxHeight: 120)
                .overlay(alignment: .topLeading) {
                    if assistant.prompt.isEmpty { Text("希望我帮你总结、润色，还是解释一段内容？").foregroundStyle(.tertiary).padding(5).allowsHitTesting(false) }
                }.disabled(assistant.isRunning)
            if !assistant.context.isEmpty {
                DisclosureGroup("本次附上的资料（\(assistant.context.count) 字）") {
                    ScrollView { Text(assistant.context).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
                    Button("移除资料") { assistant.context = "" }.disabled(assistant.isRunning)
                }
            }
            HStack {
                if assistant.isRunning { Button("停止") { assistant.stop() }; ProgressView().controlSize(.small) }
                else { Button("发送") { assistant.send() }.buttonStyle(.borderedProminent).disabled(assistant.prompt.isBlank) }
                Button("引擎与 API Key 设置") { SettingsWindowController.shared.show(tab: .engines) }
                Spacer()
                Button("回答另存为笔记") {
                    controller.notes.add(title: String(assistant.prompt.prefix(50)), body: assistant.response)
                    section = .notes
                }.disabled(assistant.response.isBlank || assistant.isRunning || controller.notes.isReadOnly)
            }
            if let error = assistant.error { errorLabel(error) }
            Divider()
            ScrollView { Text(assistant.response.isEmpty ? "回答会出现在这里。" : assistant.response)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(28)
    }

    private var networkView: some View {
        let network = controller.network
        return VStack(alignment: .leading, spacing: 18) {
            Text("网络分流").font(.title2.weight(.semibold))
            Text("复用已安装的 Go 引擎，按需检查 DNS、路由和国内外连接。不自动轮询，也不更改分流、代理或服务。")
                .foregroundStyle(.secondary)
            HStack {
                Button("检查状态") { network.refresh() }.disabled(network.isRunning)
                if network.isRunning {
                    ProgressView().controlSize(.small)
                    Button("取消") { network.cancel() }
                }
                Button("打开系统网络设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") { NSWorkspace.shared.open(url) }
                }
            }
            if let date = network.checkedAt { Text("本次检查：\(date.formatted())").font(.caption).foregroundStyle(.secondary) }
            if let error = network.error { errorLabel(error) }
            if network.checkedAt != nil {
                switch network.state {
                case .ok: Label("本次抽查通过", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .fallback: Label("当前为降级状态（FALLBACK）", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                case .bad: Label("发现网络异常，请查看检查结果", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                case .unknown: Label("尚不能确认网络状态", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                }
            }
            ScrollView { Text(network.output).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading) }
            Text("修改策略、部署或重启分流服务仍需要单独确认和系统授权。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28)
    }

    private var excerptPreview: some View {
        @Bindable var browser = controller.browser
        return VStack(alignment: .leading, spacing: 18) {
            Text("选中文字").font(.title2)
            Text(browser.excerptTitle).font(.headline)
            ScrollView { Text(browser.excerpt).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            if let url = browser.excerptURL { Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack {
                Button("取消") { browser.isPreviewing = false }
                Button("翻译") { translate(browser.excerpt); browser.isPreviewing = false }
                Spacer()
                Button("保存为笔记") {
                    controller.notes.add(title: browser.excerptTitle, body: browser.excerpt, source: browser.excerptURL)
                    browser.isPreviewing = false
                    section = .notes
                }.disabled(controller.notes.isReadOnly)
            }
        }.padding(24).frame(width: 570, height: 420)
    }

    private var recognizedTextPreview: some View {
        @Bindable var capture = controller.capture
        return VStack(alignment: .leading, spacing: 18) {
            Text("截图中的文字").font(.title2)
            TextEditor(text: $capture.recognizedText)
            HStack {
                Button("取消") { capture.isPreviewingText = false }
                Button("交给 AI") { controller.assistant.context = capture.recognizedText; section = .assistant; capture.isPreviewingText = false }
                Button("翻译") { translate(capture.recognizedText); capture.isPreviewingText = false }
                Spacer()
                Button("追加到原笔记") {
                    if let note = controller.notes.document.notes.first(where: { $0.id == capture.recognizedNoteID }) {
                        controller.notes.update(id: note.id, body: note.body.isEmpty ? capture.recognizedText : note.body + "\n\n" + capture.recognizedText)
                    }
                    capture.isPreviewingText = false
                }.disabled(controller.notes.isReadOnly)
            }
        }.padding(24).frame(width: 600, height: 440)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
    }
}

private struct WorkspaceWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct WorkspaceAttachmentView: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Label("无法读取图片", systemImage: "photo") }
        }.frame(width: 250, height: 150)
            .task(id: url) { image = NSImage(contentsOf: url) }
    }
}
