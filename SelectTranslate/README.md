# SelectTranslate · macOS 选中翻译

在支持读取选区的 App 中选中文字，就地弹出翻译。原生 Swift 编写的菜单栏小工具，默认使用 macOS 自带的**离线翻译**和**系统词典**，无需 API Key，默认引擎在本机处理文字；首次下载语言包需要联网。

Claude 默认关闭。启用后，待翻译文字及语言要求会发送到 Anthropic API，由其服务处理并返回译文；API Key 保存在登录钥匙串中。

## 功能

| 用法 | 说明 |
| --- | --- |
| 选中即翻译 | 用鼠标拖选、双击或三击选中文字，翻译面板直接弹出。面板不抢键盘焦点，可以照常复制；继续打字、按 `Esc` 或点击别处时自动关闭。可在设置里改成「显示翻译图标」（点击图标才翻译）或「不处理」 |
| 快捷键 `⌥D` | 翻译当前选中的文字；没有选中时打开输入框 |
| 快捷键 `⌥A` | 输入翻译 |
| 右键 › 服务 | 「用 SelectTranslate 翻译」，通过系统提供的文本翻译，无需辅助功能权限 |
| 菜单栏图标 | 翻译剪贴板、切换目标语言、选择划词行为、设置 |
| URL Scheme | `open "selecttranslate://translate?text=hello"`，方便接入快捷指令、Alfred、Raycast |

翻译面板：

- 自动识别原文语言，**中英互译**：原文是中文时译成英语，其他语言译成中文（可在设置里改）
- 英文单词和短语显示**牛津英汉汉英词典**释义：音标、义项、例句，支持词形还原（ran → run）和短语动词（take off）
- 原文可以直接修改，停顿后自动重新翻译；朗读原文和译文；一键复制
- 图钉固定窗口，点击外部不关闭；`Esc` 关闭；拖动顶栏移动位置

翻译引擎：

| 引擎 | 默认 | 说明 |
| --- | --- | --- |
| Apple 翻译 | 开启 | macOS 内置翻译模型，本机离线运行、免费。首次使用某组语言需要下载语言包 |
| 系统词典 | 开启 | 使用「词典」App 中启用的词典 |
| Claude | 关闭 | 可选。填入 Anthropic API Key 并启用后，将原文发送到 Anthropic API，可能产生 API 费用 |

## 安装

当前提供源码，尚无正式安装包。请按以下步骤自行构建。

运行需要 macOS 26 或更高版本。构建需要 Swift 6.2+ 和包含 macOS 26.4+ SDK 的 Xcode：源码使用了 26.4 新增的翻译策略 API，运行时会在较旧系统上回退。

构建脚本通过 `xcrun` 使用选定的 Xcode 工具链，遵循 `DEVELOPER_DIR` 和 `TOOLCHAINS`，并检查 SDK 版本；不会修改全局工具链配置。在仓库根目录执行：

```bash
cd SelectTranslate
./build.sh install
```

脚本会编译、打包并签名，然后安装到 `/Applications` 并启动；该目录不可写时使用 `~/Applications`。如果输出或安装目标的 App 仍在运行，脚本会停止并提示先正常退出，避免覆盖正在使用的应用。

默认使用 ad-hoc 签名，适合本地构建；这不代表已获 Apple 公证或通过 Gatekeeper 分发检查。首次启动后需要：

1. **开启辅助功能权限**：在弹出的提示里点「打开系统设置」，在「隐私与安全性 › 辅助功能」中打开 SelectTranslate。读取选中的文字、划词图标都依赖它。
2. **下载语言包**：第一次翻译时点面板里的「下载语言包…」，或在「设置 › 翻译引擎」中下载。

其他用法：`./build.sh` 只打包到 `dist/`，`./build.sh run` 打包后直接从 `dist/` 启动，`CONFIG=debug ./build.sh run` 构建调试版。

可用 `SIGN_IDENTITY="证书名称"` 指定已有代码签名身份。`SELECTTRANSLATE_SCRATCH_PATH` 和 `SELECTTRANSLATE_OUTPUT_DIR` 可分别指定 SwiftPM 构建目录及 App 输出目录，例如放入本次任务独有的系统临时目录；自定义目录由调用者负责清理。

## 设计

### 整体流程

```
 触发                     取词                          翻译                     展示
┌──────────────────┐    ┌──────────────────────────┐   ┌──────────────────┐   ┌───────────────────┐
│ 选中翻译 / 图标   │    │ ① 辅助功能 API             │   │ Apple 翻译（离线） │   │ 浮动翻译面板        │
│ SelectionMonitor │──▶ │   kAXSelectedText         │──▶│ 系统词典          │──▶│ 不抢焦点的 NSPanel  │
│ 快捷键            │    │ ② 网页 TextMarker 选区     │   │ Claude（可选）    │   │ + SwiftUI          │
│ HotkeyCenter     │    │ ③ 兜底：模拟 ⌘C，条件恢复    │   └──────────────────┘   └───────────────────┘
│ 服务 / URL Scheme │    │   剪贴板                   │     多个引擎并行，结果逐个出现
└──────────────────┘    └──────────────────────────┘
```

### 关键设计决策

**取词：辅助功能 API 优先，剪贴板兜底**
- 先读焦点控件的 `kAXSelectedTextAttribute`，网页内容再读 `AXSelectedTextMarkerRange`。目标 App 提供这些选区信息时，这条路不碰剪贴板。
- AX 选区不可读时，快捷键取词会尝试模拟一次 `⌘C`；识别到 Chromium / Electron 应用时，自动划词也可走此兜底。复制事件定向发送给本次选区的来源进程。仅在没有用户操作、App 切换或任务取消，且剪贴板仍是本次观察到的版本时，恢复先前已保存的数据；中断或后续写入时不覆盖当时的剪贴板。系统剪贴板没有跨进程事务，无法保证所有竞态下都完整恢复。按快捷键时会先等修饰键松开再发 `⌘C`，避免变成 `⌥⌘C`。
- 取词效果取决于目标 App、控件、系统权限及复制行为。受保护内容、不支持复制的控件或部分网页可能无法读取；自动划词也不保证覆盖所有 App，可改用手动输入或系统服务。
- AX 调用设置了 0.35 秒超时，降低目标 App 卡住时的等待影响。

**划词判定：只在"像是在选字"时弹出**
- 触发条件：拖动超过 5pt、双击、三击或 Shift 点击。
- 比较鼠标按下与松开时窗口的位置，拖动或缩放窗口不算选字。
- 关闭后可以重新拖选相同文字；只有数字和符号的选区不自动翻译。
- 新选区、用户输入、切换 App 或更改划词模式会撤销未完成的取词请求，展示前再次核对来源与请求。
- 自动弹出的面板不抢键盘焦点：⌘C 等快捷键照常作用于原 App，打字、`Esc`、点击别处时关闭。
- 选区判定过程会写入系统日志（不含文字内容），排查问题时用：
  `log show --last 10m --info --predicate 'subsystem == "com.alsay.SelectTranslate"'`

**面板：不打断当前工作**
- 使用 `nonactivatingPanel`：面板可以接收键盘输入，但原来的 App 始终在前台，关掉面板就能继续工作。
- 默认出现在鼠标右下方，下方空间不够时出现在上方；高度随内容变化，最多占屏幕 80%。
- 背景使用 macOS 26 的 Liquid Glass（`NSGlassEffectView`）。

**语言识别：先看文字系统，再用 NaturalLanguage**
- 有假名判为日语，有谚文判为韩语，汉字为主判为中文；简繁通过"转成简体后有多少字变化"区分。
- 其他语言交给 `NLLanguageRecognizer`；很短的纯 ASCII 文本（如 "OK"）没把握时按英语处理。

**词典：精确匹配词条**
- 公开的 `DCSCopyTextDefinition` 会把英文 `run` 匹配成拼音 `rùn`，所以改用 DictionaryServices 的私有接口（运行时通过 `dlsym` 加载，接口不存在时自动跳过词典），按词条精确匹配。
- 私有接口没有公开的稳定兼容保证；macOS 更新可能改变接口或行为。词典内容还取决于本机已安装并启用的词典，本文的释义示例不代表所有机器都能获得同样结果。
- 把牛津词典的纯文本整理成分行结构：词性大段、义项、例句；去掉中文后附带的拼音。
- 查不到时做词形还原（`ran → run`、`mice → mouse`），短语动词从主词条中截出对应小节。

**快捷键：Carbon `RegisterEventHotKey`**
- 不需要任何权限；被其他 App 占用时在设置中提示；录制新快捷键时暂停已注册的快捷键。

### 目录结构

```
Sources/SelectTranslate/
├── main.swift / AppDelegate.swift      启动、串联各个触发方式
├── System/
│   ├── SelectionReader.swift           取词：AX API + 剪贴板兜底
│   ├── SelectionMonitor.swift          全局鼠标监听，判断划词
│   ├── Hotkey.swift                    全局快捷键
│   └── ServiceProvider.swift           右键「服务」菜单
├── Engines/
│   ├── AppleTranslator.swift           Translation 框架（离线）
│   ├── SystemDictionary.swift          系统词典查询与排版
│   └── ClaudeTranslator.swift          Anthropic Messages API（SSE 流式，可选）
├── UI/
│   ├── TranslationPanel.swift          浮动面板的窗口和定位
│   ├── TranslationView.swift           面板内容（SwiftUI）
│   ├── TranslationViewModel.swift      语言判断、并行调度各引擎
│   ├── SelectionIcon.swift             划词图标
│   ├── StatusItemController.swift      菜单栏
│   ├── LanguagePackDownloader.swift    离线语言包下载
│   └── Settings/                       设置窗口
└── Support/                            设置存储、语言、钥匙串、权限、朗读
```

## 常见问题

**重新编译后选中翻译或快捷键取词不工作了？**
先确认运行的是预期安装位置的 App，并检查「隐私与安全性 › 辅助功能」中的授权。快捷键注册与读取其他 App 的选区是两件事，快捷键被占用或目标 App 不提供选区也会影响结果。

签名身份或程序内容变化可能影响系统对 App 的识别，ad-hoc 构建可能需要重新授权。使用同一证书与 Bundle ID 有助于保持签名身份，但不能保证任何更新都免重新授权。若已有授权条目不能使用，可正常退出目标 App，在系统设置中重新添加实际安装的 App，再启动验证；无需把权限重置作为常规构建步骤。

**右键「服务」里没有出现？**
安装后首次需要等系统刷新服务列表，可以注销重新登录，或运行 `/System/Library/CoreServices/pbs -update`。

**某个 App 里选中后没有反应？**
先检查辅助功能权限，再尝试 `⌥D` 的复制兜底；目标 App 不支持读取或复制时，请使用输入翻译或系统服务。

**选中就弹出太打扰？**
点菜单栏图标 › 「选中文字后」，改成「显示翻译图标」或「不处理（只用快捷键）」。也可以在设置里勾选「选中的是简体中文时不自动翻译」。

**词典释义是英文解释？**
词典按「词典」App 设置中的顺序查找。打开「词典」App › 设置，勾选「牛津英汉汉英词典」并拖到前面。

## URL Scheme

| 地址 | 作用 |
| --- | --- |
| `selecttranslate://translate?text=…` | 翻译指定文字 |
| `selecttranslate://selection` | 翻译当前选中的文字 |
| `selecttranslate://input` | 打开输入翻译 |
| `selecttranslate://settings?tab=general` | 打开设置（`general` / `engines` / `about`） |
