import Foundation

let cue = Passage(label: nil, text: "Um, NASA and iPhone sales did not rise by 2.5%.",
                  startMilliseconds: 1250, endMilliseconds: 3500, english: true)
func edit(_ suggestion: String) -> String {
    TranscriptEditing.edit(cue, suggestion: suggestion, beginsSentence: true)
}
precondition(edit("nasa and iphone sales did not rise by 2.5%.") == "NASA and iPhone sales did not rise by 2.5%.")
precondition(edit("NASA and iPhone sales rose by 2.5%.") == cue.text)
precondition(edit("NASA and iPhone sales did rise by 2.5%.") == cue.text)
var portuguese = cue
portuguese.english = false
portuguese.text = "um momento."
precondition(TranscriptEditing.edit(portuguese, suggestion: "momento.", beginsSentence: false) == portuguese.text)
let next = Passage(label: nil, text: "That surprised me.", startMilliseconds: 3600, endMilliseconds: 4300)
let later = Passage(label: "Sam", text: "Why?", startMilliseconds: 6500, endMilliseconds: 7000)
let cues = [cue, next, later]
precondition(TranscriptFormat.txt.render(cues, timestamps: true) ==
    "[00:00:01]  " + cue.text + " That surprised me.\n\n[00:00:06]  Sam  Why?")
precondition(TranscriptFormat.srt.render(cues, timestamps: false).contains("2\n00:00:03,600 --> 00:00:04,300"))
print("Transcript editing and export checks passed.")
