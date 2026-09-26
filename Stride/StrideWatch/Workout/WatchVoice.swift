import AVFAudio
import Foundation
import StrideKit

/// Speaks workout steps from the Watch over whatever is playing: music ducks, podcasts pause, and
/// both come back when the line ends. The workout session keeps the app running, so it also speaks
/// with the wrist down. On by default; the start list turns it off.
final class WatchVoice: NSObject {
    /// UserDefaults key on the Watch only: the Watch's speaker isn't where iPhone's coach speaks.
    nonisolated static let enabledKey = "watchVoiceSteps"

    private let synthesizer = AVSpeechSynthesizer()

    /// The best installed US English voice, like the coach on iPhone.
    private static let voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "en-US" }
        .max { $0.quality.rawValue < $1.quality.rawValue }
        ?? AVSpeechSynthesisVoice(language: "en-US")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isEnabled: Bool { StrideSettings.bool(Self.enabledKey) }

    /// Queues a line, unless the runner turned spoken steps off.
    func speak(_ text: String) {
        guard isEnabled else { return }
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

    /// Other audio stays ducked while the session is active, so it ends after the last line.
    fileprivate func deactivateIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension WatchVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateIfIdle() }
    }
}
