import AVFoundation

/// 朗读原文 / 译文；再次点击同一段文字时停止
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var currentText: String?

    func toggle(_ text: String, voiceLanguage: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            if currentText == text {
                currentText = nil
                return
            }
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        currentText = text
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentText = nil
    }
}
