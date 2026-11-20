import Foundation

enum TranscriptFormat: String, CaseIterable {
    case txt, srt, vtt
    var title: String {
        switch self {
        case .txt: return "Plain text (.txt)"
        case .srt: return "SubRip subtitles (.srt)"
        case .vtt: return "WebVTT subtitles (.vtt)"
        }
    }
    func render(_ passages: [Passage], timestamps: Bool) -> String {
        if self == .txt { return TranscriptEditing.paragraphs(passages, timestamps: timestamps) }
        func time(_ ms: Int) -> String {
            let t = max(0, ms)
            let base = String(format: "%02d:%02d:%02d", t/3600000, t/60000%60, t/1000%60)
            return base + (self == .vtt ? "." : ",") + String(format: "%03d", t%1000)
        }
        var result = self == .vtt ? "WEBVTT\n\n" : ""
        for (i,p) in passages.enumerated() {
            if self == .srt { result += "\(i+1)\n" }
            let end = max(p.startMilliseconds + 1, p.endMilliseconds)
            result += "\(time(p.startMilliseconds)) --> \(time(end))\n"
            let caption = (p.label.map { $0 + ": " } ?? "") + p.text
            // Keep subtitle markup and cue separators out of the payload.
            result += caption.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;") + "\n\n"
        }
        return result
    }
}

struct SpeechSettings: Equatable {
    let recording: URL
    let modified: Date?
    let model, language: String
    let stereo, translate: Bool
}
