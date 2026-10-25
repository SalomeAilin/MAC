import SwiftUI

struct AboutView: View {
    private let settings = AppSettings.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("SelectTranslate")
                    .font(.title2.weight(.semibold))
                Text("版本 \(version)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                tip("cursorarrow.rays", "选中文字后，光标在选区内停留一秒才自动翻译")
                tip("book.closed", "菜单栏「打开工作台」：日记、网页资料、AI、截图与网络状态")
                tip("keyboard", "选中文字后按 \(settings.selectionHotkey?.displayString ?? "快捷键")")
                tip("character.cursor.ibeam", "按 \(settings.inputHotkey?.displayString ?? "快捷键") 打开输入翻译，或在面板里直接修改原文")
                tip("contextualmenu.and.cursorarrow", "右键菜单 › 服务 › 用 SelectTranslate 翻译")
                tip("pin", "点面板上的图钉可以固定窗口，按 Esc 关闭")
                tip("link", "自动化：open \"selecttranslate://translate?text=hello\"")
            }
            .frame(maxWidth: 420, alignment: .leading)

            Spacer()
        }
        .padding(28)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).textSelection(.enabled)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
        }
    }
}
