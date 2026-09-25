import AVFoundation
import StrideKit

/// Speaks coach lines over whatever the runner is listening to: music ducks, podcasts pause, and
/// everything resumes when the line ends. Works with the screen locked (audio background mode).
final class VoiceCoach: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// The best installed US English voice (premium, then enhanced, then default).
    private static let voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "en-US" }
        .max { $0.quality.rawValue < $1.quality.rawValue }
        ?? AVSpeechSynthesisVoice(language: "en-US")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isEnabled: Bool { StrideSettings.bool(StrideSettings.voiceCoach) }

    /// Queues a line. `force` speaks even with the coach turned off (the "Test voice" button).
    func speak(_ text: String, force: Bool = false) {
        guard force || isEnabled else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        utterance.postUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateIfIdle()
    }

    fileprivate func deactivateIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateIfIdle() }
    }
}
