import AppKit

private func label(_ value: String, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: value)
    field.font = .systemFont(ofSize: size, weight: weight)
    return field
}
private func column(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
}
private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    return stack
}
private func pin(_ child: NSView, _ parent: NSView, _ margin: CGFloat) {
    parent.addSubview(child)
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: margin),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -margin),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: margin),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -margin)])
}


final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = ModelStore()
    var window: NSWindow!
    private var library: NSWindow?
    private var libraryButtons = [NSButton]()
    private let libraryStatus = label("")
    private var audio: URL?
    private var job: RecordingJob?
    private var raw = [Passage](), edited = [Passage](), saved = true
    private var lastSettings: SpeechSettings?
    private let language = NSPopUpButton()
    private let translate = NSButton(checkboxWithTitle: "Translate into English", target: nil, action: nil)
    private var settings: SpeechSettings? {
        guard let file = audio else { return nil }
        return SpeechSettings(recording: file, modified: (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                              model: selected.file, language: selected.turns ? "en" : language.selectedItem?.representedObject as? String ?? "auto",
                              stereo: mode.indexOfSelectedItem == 1, translate: translate.isEnabled && translate.state == .on)
    }
    private var reuse: Bool { !raw.isEmpty && lastSettings == settings && cleanup.state == .on }
    private let stamps = NSButton(checkboxWithTitle: "Include timestamps", target: nil, action: nil)
    private let source = label("No recording selected", 13, .medium)
    private let speech = NSPopUpButton(), mode = NSPopUpButton()
    private let cleanup = NSButton(checkboxWithTitle: "Remove filler words", target: nil, action: nil)
    private let note = label("", 12), modelNote = label("", 12)
    private let status = label("Ready", 12)
    private let timing = label("", 12)
    private let bar = NSProgressIndicator()
    private var clock: Timer?
    private var started: TimeInterval = 0, stageStarted: TimeInterval = 0
    private var percent: Int?
    private let spinner = NSProgressIndicator()
    private let output = NSTextView()
    private let version = NSSegmentedControl()
    private var choose: NSButton!, start: NSButton!, copy: NSButton!, save: NSButton!
    private var speechModels: [Model] { store.catalog.filter { !$0.cleanup } }
    private var selected: Model { speechModels[speech.indexOfSelectedItem] }
    private var editor: Model { store.catalog.first { $0.cleanup }! }
    private var missing: Model? {
        if !reuse && !store.installed(selected) { return selected }
        if cleanup.state == .on && !store.installed(editor) { return editor }
        return nil
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), root = NSMenuItem()
        menu.addItem(root)
        let appMenu = NSMenu()
        root.submenu = appMenu
        appMenu.addItem(withTitle: "About Transcriber", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Transcriber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu?.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 940,height: 630),
                          styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "Transcriber"
        window.minSize = NSSize(width: 850,height: 625)
        window.delegate = self
        window.isReleasedWhenClosed = false
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.widthAnchor.constraint(equalToConstant: 292).isActive = true
        let heading = label("Transcriber", 32, .bold)
        let subtitle = label("Private audio transcription", 13)
        subtitle.textColor = .secondaryLabelColor
        choose = button("Choose recording…", #selector(pick))
        source.lineBreakMode = .byTruncatingMiddle
        source.maximumNumberOfLines = 1
        speech.addItems(withTitles: speechModels.map(\.title))
        if let last = UserDefaults.standard.string(forKey: "speechModel"),
           let i = speechModels.firstIndex(where: { $0.file == last }) { speech.selectItem(at: i) }
        speech.target = self; speech.action = #selector(changeModel)
        language.addItem(withTitle: "Detect automatically")
        language.lastItem?.representedObject = "auto"
        let table = try! String(contentsOf: Bundle.main.url(forResource: "Languages", withExtension: "txt")!, encoding: .utf8)
        for line in table.split(separator: "\n") {
            let fields = line.components(separatedBy: "\t")
            language.addItem(withTitle: fields[1]); language.lastItem?.representedObject = fields[0]
        }
        language.target = self; language.action = #selector(refresh)
        translate.target = self; translate.action = #selector(refresh)
        mode.addItems(withTitles: ["Continuous transcript","Left / right speakers"])
        mode.target = self; mode.action = #selector(refresh)
        cleanup.target = self; cleanup.action = #selector(refresh)
        let libraryButton = button("Model library…", #selector(openLibrary))
        start = button("Transcribe", #selector(begin))
        start.keyEquivalent = "\r"
        let spacer = NSView()
        let side = column([heading,subtitle,label("Recording",15,.semibold),source,choose,
                           label("Speech model",15,.semibold),speech,modelNote,libraryButton,
                           label("Spoken language",15,.semibold),language,translate,
                           label("Speakers",15,.semibold),mode,note,cleanup,
                           spacer,start], spacing: 5)
        for v in [subtitle,choose!,libraryButton,translate,note] { side.setCustomSpacing(11, after: v) }
        for v in [speech,mode,language,source,note,modelNote,start!] { v.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true }
        pin(side,sidebar,20)
        let page = NSView()
        let heading2 = label("Transcript", 29, .semibold)
        version.segmentCount = 2
        version.setLabel("Original", forSegment: 0); version.setLabel("Cleaned", forSegment: 1)
        version.selectedSegment = 0; version.target = self; version.action = #selector(display)
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        output.isEditable = false; output.isSelectable = true; output.isRichText = false
        output.font = .systemFont(ofSize: 16); output.textContainerInset = NSSize(width: 16,height: 18)
        output.isVerticallyResizable = true; output.autoresizingMask = [.width]
        output.textContainer?.widthTracksTextView = true; scroll.documentView = output
        copy = button("Copy", #selector(copyText)); save = button("Export…", #selector(exportMenu))
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let bottom = row([spinner,status,NSView(),copy,save])
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 100
        timing.textColor = .secondaryLabelColor
        stamps.target = self; stamps.action = #selector(toggleTimestamps)
        stamps.state = UserDefaults.standard.bool(forKey: "timestamps") ? .on : .off
        let main = column([heading2,row([version,stamps]),scroll,bar,timing,bottom],spacing: 12)
        bar.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true
        bar.isHidden = true; timing.isHidden = true
        for v in [scroll,bottom] { v.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        pin(main,page,24)
        let split = row([sidebar,page]); split.spacing = 0; split.alignment = .top
        window.contentView = NSView()
        pin(split,window.contentView!,0)
        for v in [sidebar,page] { v.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true }
        store.status = { [weak self] s in self?.libraryStatus.stringValue = s; self?.status.stringValue = s; self?.refresh() }
        store.finished = { [weak self] m,e in
            guard let self = self else { return }
            let msg = e.map { ($0 as NSError).code == NSURLErrorCancelled ? "Download cancelled." : $0.localizedDescription } ?? "\(m.title) is ready."
            self.libraryStatus.stringValue = msg; self.status.stringValue = msg; self.refresh()
        }
        display(); refresh()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func changeModel() {
        UserDefaults.standard.set(selected.file, forKey: "speechModel")
        refresh()
    }
    @objc private func refresh() {
        let idle = job == nil
        choose.isEnabled = idle; speech.isEnabled = idle; cleanup.isEnabled = idle
        language.isEnabled = idle && !selected.turns
        let englishOnly = selected.turns
        let turbo = selected.file.contains("turbo")
        language.itemArray.first { ($0.representedObject as? String) == "yue" }?.isEnabled = turbo
        language.autoenablesItems = false
        if englishOnly { language.selectItem(at: language.indexOfItem(withRepresentedObject: "en")) }
        if !turbo && language.selectedItem?.representedObject as? String == "yue" { language.selectItem(at: 0) }
        translate.isEnabled = idle && !englishOnly && !turbo
        if englishOnly || turbo { translate.state = .off }
        translate.toolTip = turbo ? "Choose Base, Tiny, or Small to translate speech into English." : nil
        mode.isEnabled = idle && !selected.turns
        mode.item(at: 0)?.title = selected.turns ? "Mark speaker changes" : "Continuous transcript"
        if selected.turns { mode.selectItem(at: 0) }
        note.stringValue = selected.turns ? "Marks likely changes of speaker in English recordings." :
            (mode.indexOfSelectedItem == 1 ? "For stereo recordings with a different voice on each channel." : "For interviews, try the Speaker Turns model.")
        modelNote.stringValue = "\(selected.detail) · \(selected.size)"
        for v in [note,modelNote] { v.textColor = .secondaryLabelColor }
        if !idle { start.title = "Stop transcription"; start.isEnabled = true }
        else if let m = missing {
            start.title = store.pending == nil ? "Download \(m.title) (\(m.size))" : "Download in progress…"
            start.isEnabled = store.pending == nil
        } else if reuse { start.title = edited.isEmpty ? "Clean existing transcript" : "Show cleaned transcript"; start.isEnabled = true
        } else { start.title = "Transcribe recording"; start.isEnabled = audio != nil }
        for b in libraryButtons {
            let m = store.catalog[b.tag]
            let active = !idle && (selected.file == m.file || (m.cleanup && cleanup.state == .on))
            let downloading = store.pending?.file == m.file
            b.title = active ? "In use" : downloading ? "Cancel" : store.installed(m) ? "Delete…" : "Download"
            b.isEnabled = !active && (downloading || store.installed(m) || store.pending == nil)
        }
        save.isEnabled = !raw.isEmpty; copy.isEnabled = save.isEnabled
    }
    @objc private func openLibrary() {
        if library == nil {
            let panel = NSWindow(contentRect: NSRect(x:0,y:0,width:510,height:475), styleMask:[.titled,.closable],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed = false; panel.title = "Model library"
            let title = label("Model library",24,.bold)
            let desc = label("Download once, then work offline. Recordings and transcripts stay on your Mac.")
            let stack = column([title,desc],spacing: 12)
            desc.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            for (i,m) in store.catalog.enumerated() {
                let b = button("",#selector(modelAction(_:))); b.tag = i; libraryButtons.append(b)
                let sub = label("\(m.detail) · \(m.size)",12); sub.textColor = .secondaryLabelColor
                let r = row([column([label(m.title,14,.semibold),sub],spacing:2),NSView(),b])
                stack.addArrangedSubview(r); r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(NSView()); stack.addArrangedSubview(libraryStatus)
            panel.contentView = NSView(); pin(stack,panel.contentView!,20); library = panel
        }
        refresh(); library?.center(); library?.makeKeyAndOrderFront(nil)
    }
    @objc private func modelAction(_ sender: NSButton) {
        let model = store.catalog[sender.tag]
        if store.pending?.file == model.file { store.cancel(); return }
        if store.installed(model) {
            guard confirm("Delete \(model.title)?", "This frees \(model.size). You can download it again later.", "Delete") else { return }
            do { try FileManager.default.removeItem(at: store.path(model)); libraryStatus.stringValue = "Deleted \(model.title)." }
            catch { libraryStatus.stringValue = error.localizedDescription }
        } else { store.download(model) }
        refresh()
    }
    private func confirm(_ title: String,_ detail: String,_ action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: action)
        return alert.runModal() == .alertSecondButtonReturn
    }
    @objc private func pick() {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.prompt = "Choose recording"
        if p.runModal() == .OK, let url = p.url {
            audio = url; source.stringValue = url.lastPathComponent; source.toolTip = url.path; refresh()
        }
    }
    @objc private func begin() {
        if let job = job { job.cancel(); status.stringValue = "Stopping…"; return }
        if let m = missing { store.download(m); return }
        guard let audio = audio, let configuration = settings else { return }
        let cached = reuse ? raw : []
        if !cached.isEmpty && !edited.isEmpty { version.selectedSegment = 1; display(); return }
        if cached.isEmpty && !saved && !confirm("Replace this transcript?", "Save any text you want to keep before starting another recording.", "Replace") { return }
        let work = RecordingJob(tools: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers"))
        job = work
        started = ProcessInfo.processInfo.systemUptime
        stageStarted = started; percent = nil; timing.isHidden = false
        updateTime()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateTime() }
        work.progress = { value in DispatchQueue.main.async {
            self.percent = value; self.bar.doubleValue = Double(value); self.bar.isHidden = false; self.updateTime()
        } }
        transcriptName = audio.deletingPathExtension().lastPathComponent
        let model = store.path(selected), turns = selected.turns, stereo = mode.indexOfSelectedItem == 1
        let cleanupModel = cleanup.state == .on ? store.path(editor) : nil
        if cached.isEmpty { raw = []; edited = []; lastSettings = nil }
        version.selectedSegment = 0; display(); spinner.startAnimation(nil); refresh()
        let update: (String) -> Void = { s in DispatchQueue.main.async {
            self.status.stringValue = s; self.stageStarted = ProcessInfo.processInfo.systemUptime
            self.percent = nil; self.bar.isHidden = true; self.updateTime()
        } }
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? FileManager.default.removeItem(at: work.directory) }
            var message = "Transcript ready."
            do {
                var passages = cached
                if passages.isEmpty {
                    let fresh = try work.transcribe(audio: audio, model: model, stereo: stereo, turns: turns,
                                                    language: configuration.language, translate: configuration.translate, status: update)
                    passages = fresh
                    DispatchQueue.main.async {
                        self.raw = fresh; self.lastSettings = configuration; self.saved = false; self.display(); self.refresh()
                    }
                } else {
                    try FileManager.default.createDirectory(at: work.directory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                }
                if let m = cleanupModel {
                    let clean = try work.clean(passages, model: m, status: update)
                    DispatchQueue.main.async { self.edited = clean; self.saved = false; self.version.selectedSegment = 1; self.display() }
                }
            } catch { message = error.localizedDescription }
            let final = message
            DispatchQueue.main.async {
                self.clock?.invalidate(); self.clock = nil; self.percent = nil; self.updateTime()
                self.bar.isHidden = true; self.job = nil; self.status.stringValue = final; self.spinner.stopAnimation(nil); self.display(); self.refresh()
            }
        }
    }
    private func updateTime() {
        let now = ProcessInfo.processInfo.systemUptime
        func duration(_ seconds: TimeInterval) -> String {
            let sec = max(0, Int(seconds))
            if sec >= 3600 { return String(format: "%d:%02d:%02d", sec/3600, sec/60%60, sec%60) }
            return String(format: "%d:%02d", sec/60, sec%60)
        }
        var text = "Elapsed " + duration(now - started)
        if let percent = percent {
            text += "  ·  \(percent)% transcribed"
            if percent >= 5 && percent < 100 {
                let remaining = (now - stageStarted) * Double(100 - percent) / Double(percent)
                text += "  ·  About " + duration(remaining) + " left in transcription"
            }
        }
        timing.stringValue = text
    }
    @objc private func toggleTimestamps() {
        UserDefaults.standard.set(stamps.state == .on, forKey: "timestamps")
        display()
    }
    @objc private func display() {
        version.setEnabled(!edited.isEmpty, forSegment: 1)
        if raw.isEmpty {
            output.string = job == nil ? "Choose a recording and a speech model to start your transcript." : "Your transcript will appear here."
            output.textColor = .secondaryLabelColor
        } else {
            output.textColor = .textColor; output.string = TranscriptFormat.txt.render(version.selectedSegment == 1 ? edited : raw, timestamps: stamps.state == .on)
        }
        output.scrollRangeToVisible(NSRange(location: 0,length: 0))
    }
    @objc private func copyText() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output.string,forType:.string)
        status.stringValue = "Copied to clipboard."
    }
    @objc private func exportMenu() {
        let menu = NSMenu()
        for format in TranscriptFormat.allCases {
            let item = menu.addItem(withTitle: format.title, action: #selector(exportFile(_:)), keyEquivalent: "")
            item.representedObject = format.rawValue; item.target = self
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: save.bounds.minY), in: save)
    }
    @objc private func exportFile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let format = TranscriptFormat(rawValue: id) else { return }
        let p = NSSavePanel(); p.allowedFileTypes = [format.rawValue]
        p.nameFieldStringValue = (transcriptName ?? "Transcript") + (version.selectedSegment == 1 ? " - cleaned." : ".") + format.rawValue
        if p.runModal() == .OK, let url = p.url {
            do {
                let text = format.render(version.selectedSegment == 1 ? edited : raw, timestamps: stamps.state == .on)
                try text.write(to:url,atomically:true,encoding:.utf8); saved = true; status.stringValue = "Saved \(url.lastPathComponent)."
            } catch { status.stringValue = error.localizedDescription }
        }
    }
    private var transcriptName: String?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil); return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if job != nil || store.pending != nil || !saved {
            guard confirm("Quit Transcriber?", "Any active work will stop and unsaved transcript text will be lost.", "Quit") else { return .terminateCancel }
        }
        job?.cancel(); store.cancel(); return .terminateNow
    }
}
