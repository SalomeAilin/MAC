import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 点击后按下新的快捷键组合；Esc 取消
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    var conflict = false

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if conflict, !isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("这个快捷键已被其他 App 占用，请换一个")
            }
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "请按下快捷键…" : (combo?.displayString ?? "点击设置"))
                    .frame(minWidth: 96)
            }
            if combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("清除快捷键")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        // 暂停已注册的全局快捷键，否则按下旧组合会直接触发翻译
        HotkeyCenter.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard KeyCombo.isValid(keyCode: Int(event.keyCode), modifiers: modifiers) else {
                NSSound.beep()
                return nil
            }
            combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            HotkeyCenter.shared.isPaused = false
        }
    }
}
