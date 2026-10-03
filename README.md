# ScriptFollower

**A teleprompter that follows your voice.** Give it a script and the live transcript from a speech
recognizer; it tells you which word the reader is on, so the prompter scrolls itself.

This is the alignment engine behind the voice-following teleprompter in
[Subtitles AI](https://apps.apple.com/app/id1247835812) (iPhone, iPad, Mac), extracted and ported to Swift.

## Why it's harder than it looks

A naive "find the last heard word in the script" falls apart in real use:

| Real-world problem | How ScriptFollower handles it |
|---|---|
| The recognizer mishears ("chanel", "todays") | Fuzzy word match: exact, a plural/tense away, or within an edit distance of 1–2 (bounded Levenshtein with early exit) |
| The reader says "um", "uh", "the", "a" | Short words alone never move the position |
| The same phrase appears twice in the script | Ties go to the nearest occurrence; the search window is bounded (3 back, 40 ahead) |
| The reader skips a sentence | Allowed, but a long jump needs a matching *phrase*, not one word (1 / 2 / 3 matching words by jump size) |
| The recognizer revises its last words | The last 6 heard words are scored with an LCS against the script window, not matched one by one |
| The reader scrolls by hand | Set `currentIndex` to re-anchor |

It only ever moves forward, it's Foundation-only (no audio, no UI), and it runs in microseconds per update.

## Usage

```swift
import ScriptFollower

var aligner = ScriptAligner(script: scriptText)

// In your SFSpeechRecognizer partial-result handler:
let heard = ScriptAligner.normalizedWords(in: result.bestTranscription.formattedString)
if aligner.consume(heard: heard) {
    scrollTo(wordIndex: aligner.currentIndex)
}
```

A complete SwiftUI teleprompter (microphone, on-device recognition when available, auto-scroll with a
reading line at 36% of the screen) is in [`Examples/TeleprompterView.swift`](Examples/TeleprompterView.swift).

## Tests

```
swift test
```

Covers word-by-word following, misheard words, filler words, never moving backward, repeated phrases,
and skipped sentences.

## Requirements

iOS 15+ / macOS 12+, Swift 5.9+.

## License

MIT
