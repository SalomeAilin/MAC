# MAC

用于整理 macOS 相关工具、配置和使用文档的开源项目。

## 项目

| 项目 | 说明 | 运行环境 |
| --- | --- | --- |
| [SelectTranslate](SelectTranslate/README.md) | 原生 Swift 菜单栏翻译工具：选中英文即在鼠标旁弹出译文，也支持图标、快捷键和系统服务入口 | macOS 26+，Apple Silicon / Intel；构建要求见项目说明 |

SelectTranslate 默认并排显示谷歌翻译和 Apple 本机翻译，英文单词附带系统词典释义，不需要 API Key。谷歌翻译开启时（默认开启），待翻译文字会发送给谷歌，可以在设置中关闭；首次使用 Apple 翻译语言对可能需要下载语言包。可选的 Claude 引擎需要自行配置 API Key，开启后待翻译文字会发送到 Anthropic。

## 下载安装

在 [SelectTranslate 1.1.0 Release](https://github.com/SalomeAilin/MAC/releases/tag/selecttranslate-v1.1.0) 下载通用版 DMG 或 ZIP。DMG 打开后，将 App 拖入 Applications；ZIP 解压后，将 App 拖入「应用程序」。两个包都适用于 Apple Silicon 和 Intel Mac，下载用户无需安装 Xcode 或运行签名脚本。

当前发行包使用 ad-hoc 签名，未经 Apple 公证。首次打开若被系统阻止，确认来源后，按 [Apple 官方说明](https://support.apple.com/en-us/102445) 在「系统设置 › 隐私与安全性」中选择「仍要打开」。校验文件、权限设置和源码构建步骤见 [SelectTranslate 使用说明](SelectTranslate/README.md#安装)。

## 获取仓库

```sh
git clone https://github.com/SalomeAilin/MAC.git
cd MAC
```

## 仓库内容

| 文件或目录 | 用途 |
| --- | --- |
| [README.md](README.md) | 项目说明与使用入口 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 问题反馈与贡献指南 |
| [SECURITY.md](SECURITY.md) | 安全问题报告方式 |
| [AGENTS.md](AGENTS.md) | 开发协作、环境保护和任务收尾约定 |
| [.github/](.github/) | Issue 表单与 Pull Request 模板 |
| [.editorconfig](.editorconfig)、[.gitattributes](.gitattributes) | 文本格式与换行规则 |
| [.gitignore](.gitignore) | 本地配置、日志和 macOS 元数据的忽略规则 |
| [LICENSE](LICENSE) | MIT 许可证 |
| [SelectTranslate/](SelectTranslate/) | 选中翻译工具的源码、资源与构建脚本 |

各项目的源码、资源和使用说明放在对应子目录，按用途归档。本机配置及私有资料放入被 Git 忽略的 `local/` 目录；构建输出遵循各项目的忽略规则。

## 参与贡献

欢迎通过 [Issues](https://github.com/SalomeAilin/MAC/issues) 反馈问题或提出建议，通过 Pull Request 提交改进。提交前请阅读 [贡献指南](CONTRIBUTING.md)。

涉及凭据泄露或其他安全问题，请使用 [安全问题报告入口](SECURITY.md)。

## 许可证

本项目使用 [MIT 许可证](LICENSE)。
