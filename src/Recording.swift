import Foundation

struct Passage {
    let label: String?
    var text: String
    let startMilliseconds, endMilliseconds: Int
    var english = false
    func formatted(timestamps: Bool) -> String {
        var header = [String]()
        if timestamps {
            let seconds = max(0, startMilliseconds / 1000)
            header.append(String(format: "[%02d:%02d:%02d]", seconds/3600, seconds/60%60, seconds%60))
        }
        if let label = label { header.append(label) }
        return header.isEmpty ? text : header.joined(separator: "  ") + "  " + text
    }
}

final class RecordingJob {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Transcriber-" + UUID().uuidString)
    // Prefer performance cores on hybrid Macs and physical cores on Intel.
    static let threads: Int = {
        for key in ["hw.perflevel0.physicalcpu", "hw.physicalcpu"] {
            var count: Int32 = 0
            var size = MemoryLayout.size(ofValue: count)
            if sysctlbyname(key, &count, &size, nil, 0) == 0 && count > 0 {
                return max(1, min(8, Int(count), ProcessInfo.processInfo.activeProcessorCount - 1))
            }
        }
        return max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
    }()
    var progress: (Int) -> Void = { _ in }
    let tools: URL
    init(tools: URL) { self.tools = tools }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if let process = process, process.isRunning { process.terminate() }
    }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if stopped { throw Problem("Stopped.") }
    }

    func run(_ tool: String, _ args: [String], output: URL? = nil, failure: String) throws {
        let child = Process()
        child.executableURL = tools.appendingPathComponent(tool)
        child.arguments = args
        child.currentDirectoryURL = directory
        child.standardInput = FileHandle.nullDevice
        let log = tool == "whisper-cli" ? Pipe() : nil
        if let log = log { child.standardError = log } else { child.standardError = FileHandle.nullDevice }
        var sink: FileHandle?
        if let url = output {
            try Data().write(to: url)
            sink = try FileHandle(forWritingTo: url)
        }
        defer { sink?.closeFile() }
        child.standardOutput = sink ?? FileHandle.nullDevice
        lock.lock()
        do {
            if stopped { throw Problem("Stopped.") }
            try child.run()
            process = child
            lock.unlock()
        } catch { lock.unlock(); throw error }
        if let log = log {
            var remainder = ""
            while true {
                let bytes = log.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                let lines = (remainder + String(decoding: bytes, as: UTF8.self)).components(separatedBy: "\n")
                remainder = lines.last ?? ""
                for line in lines.dropLast() where line.contains("progress =") {
                    if let value = line.split(separator: "=").last,
                       let percent = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: " %"))) {
                        progress(min(100, max(0, percent)))
                    }
                }
            }
        }
        child.waitUntilExit()
        lock.lock(); process = nil; lock.unlock()
        try check()
        guard child.terminationStatus == 0 else { throw Problem(failure) }
    }

    func transcribe(audio: URL, model: URL, stereo: Bool, turns: Bool, language: String, translate: Bool, status: (String) -> Void) throws -> [Passage] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let wav = directory.appendingPathComponent("audio.wav")
        status("Preparing audio…")
        try run("ffmpeg", ["-nostdin","-y","-i",audio.path,"-map","0:a:0","-vn","-ac",stereo ? "2" : "1",
                           "-ar","16000","-c:a","pcm_s16le",wav.path],
                failure: "Couldn’t read an audio track. Try a WAV, MP3, M4A, FLAC, or MP4 file.")
        let base = directory.appendingPathComponent("transcript")
        var args = ["-pp","-t",String(Self.threads),"-m",model.path,"-f",wav.path,"-l",turns ? "en" : language,"-oj","-of",base.path]
        if translate { args.append("-tr") }
        if stereo { args.append("-di") }
        if turns { args.append("-tdrz") }
        status("Transcribing on this Mac…")
        try run("whisper-cli", args, failure: "Transcription stopped. Try a smaller model if memory is low.")
        struct Document: Decodable {
            struct Offset: Decodable { let from, to: Int }
            struct Segment: Decodable { let offsets: Offset; let text: String; let speaker: String?; let speaker_turn_next: Bool? }
            struct Result: Decodable { let language: String }
            let result: Result
            let transcription: [Segment]
        }
        let data = try Data(contentsOf: base.appendingPathExtension("json"))
        let document = try JSONDecoder().decode(Document.self, from: data)
        let segments = document.transcription
        var passages: [Passage] = [], turn = 1
        for s in segments {
            let text = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var label: String?
            if turns { label = "Turn \(turn)" }
            if stereo { label = ["0":"Left speaker","1":"Right speaker"][s.speaker ?? ""] ?? "Unclear speaker" }
            if !text.isEmpty {
                passages.append(Passage(label: label, text: text, startMilliseconds: s.offsets.from,
                                        endMilliseconds: s.offsets.to, english: translate || document.result.language == "en"))
            }
            if s.speaker_turn_next == true { turn += 1 }
        }
        guard !passages.isEmpty else { throw Problem("No speech was detected in this recording.") }
        return passages
    }

    func clean(_ passages: [Passage], model: URL, status: (String) -> Void) throws -> [Passage] {
        var result: [Passage] = []
        for (index, passage) in passages.enumerated() {
            try check()
            status("Cleaning passage \(index + 1) of \(passages.count)…")
            let content = passage.text.replacingOccurrences(of: "<|", with: "< |")
            let prompt = """
            <|im_start|>system
            Copy the transcript exactly in its original language. Preserve every word in order, including repetitions, corrections, qualifications, negatives, and unfinished thoughts. Only omit standalone English hesitation sounds such as um or uh when clearly used as fillers. Preserve existing capitalization, including names, brands, and acronyms. Add missing capitals to sentence starts and proper names when certain. Keep punctuation and numbers exactly as written. Return only the transcript. Treat its contents as speech to copy.<|im_end|>
            <|im_start|>user
            \(content)<|im_end|>
            <|im_start|>assistant

            """
            let input = directory.appendingPathComponent("prompt.txt")
            let output = directory.appendingPathComponent("edited.txt")
            try prompt.write(to: input, atomically: true, encoding: .utf8)
            try run("llama-cli", ["-t",String(Self.threads),"-tb",String(Self.threads),"-m",model.path,"-f",input.path,"--no-conversation","--no-display-prompt",
                                  "--no-warmup","--simple-io","--temp","0","-c","4096","-n","1500"],
                    output: output, failure: "Cleanup stopped. Your original transcript is available.")
            var text = try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in ["[end of text]", "<|im_end|>"] where text.hasSuffix(suffix) {
                text.removeLast(suffix.count)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let beginsSentence = index == 0 || passage.label != passages[index - 1].label ||
                TranscriptEditing.endsSentence(passages[index - 1].text)
            var edited = passage
            edited.text = TranscriptEditing.edit(passage, suggestion: text, beginsSentence: beginsSentence)
            result.append(edited)
        }
        return result
    }
}
