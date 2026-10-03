import os

/// 诊断日志，用「控制台」App 或以下命令查看（不会记录选中文字的内容）：
/// log show --last 10m --info --predicate 'subsystem == "com.alsay.SelectTranslate"'
nonisolated let selectionLog = Logger(subsystem: "com.alsay.SelectTranslate", category: "selection")
