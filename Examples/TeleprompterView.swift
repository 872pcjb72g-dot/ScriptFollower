// A minimal voice-following teleprompter built on ScriptAligner.
// Drop into an iOS 15+ app target; add NSMicrophoneUsageDescription and
// NSSpeechRecognitionUsageDescription to Info.plist.

import SwiftUI
import Speech
import AVFoundation
import ScriptFollower

@MainActor
final class VoiceFollower: ObservableObject {
    @Published private(set) var wordIndex = -1
    @Published private(set) var isListening = false

    private var aligner: ScriptAligner
    private let recognizer = SFSpeechRecognizer()
    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(script: String) { aligner = ScriptAligner(script: script) }

    func start() async throws {
        guard await withCheckedContinuation({ c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } })
        else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audio.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audio.prepare()
        try audio.start()
        isListening = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in
                guard let self else { return }
                if self.aligner.consume(heard: ScriptAligner.normalizedWords(in: text)) {
                    self.wordIndex = self.aligner.currentIndex
                }
            }
        }
    }

    func stop() {
        audio.stop()
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        isListening = false
    }
}

struct TeleprompterView: View {
    let script: String
    @StateObject private var follower: VoiceFollower
    private let words: [String]

    init(script: String) {
        self.script = script
        // Display words; ScriptAligner tokenizes the same way, so indices line up.
        var display: [String] = []
        script.enumerateSubstrings(in: script.startIndex..., options: [.byWords, .localized]) { w, _, _, _ in
            if let w, !ScriptAligner.normalize(w).isEmpty { display.append(w) }
        }
        words = display
        _follower = StateObject(wrappedValue: VoiceFollower(script: script))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                FlowText(words: words, current: follower.wordIndex)
                    .padding(24)
            }
            .onChange(of: follower.wordIndex) { i in
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(i, anchor: UnitPoint(x: 0.5, y: 0.36)) }
            }
        }
        .background(Color.black)
        .safeAreaInset(edge: .bottom) {
            Button(follower.isListening ? "Stop" : "Start") {
                if follower.isListening { follower.stop() } else { Task { try? await follower.start() } }
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

/// Words laid out as wrapped lines; spoken words dim, the current one is highlighted.
private struct FlowText: View {
    let words: [String]
    let current: Int

    var body: some View {
        // One Text per line of ~6 words keeps scrollTo targets cheap for a demo.
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(stride(from: 0, to: words.count, by: 6)), id: \.self) { start in
                let end = min(start + 6, words.count)
                (start..<end).reduce(Text("")) { line, i in
                    line + Text(words[i] + " ")
                        .foregroundColor(i < current ? .gray : (i == current ? .yellow : .white))
                }
                .font(.system(size: 34, weight: .semibold))
                .id(start..<end ~= current ? current : start)
            }
        }
    }
}
