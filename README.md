# MAC

用于整理 macOS 相关工具、配置和使用文档的开源项目。

## 项目

| 项目 | 说明 | 运行环境 |
| --- | --- | --- |
| [SelectTranslate](SelectTranslate/README.md) | 原生 Swift 菜单栏翻译工具：选中英文即在鼠标旁弹出译文，也支持图标、快捷键和系统服务入口 | macOS 26+；构建要求见项目说明 |

SelectTranslate 默认并排显示谷歌翻译和 Apple 本机翻译，英文单词附带系统词典释义，不需要 API Key。谷歌翻译开启时（默认开启），待翻译文字会发送给谷歌，可以在设置中关闭；首次使用 Apple 翻译语言对可能需要下载语言包。可选的 Claude 引擎需要自行配置 API Key，开启后待翻译文字会发送到 Anthropic。

当前提供源码构建方式，尚未发布供下载的安装包。构建、权限设置及功能限制请阅读各项目的 README。

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
