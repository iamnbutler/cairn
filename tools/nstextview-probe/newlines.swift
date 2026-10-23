// NSTextView behaviour probe for docs/text.md. Run: swiftc newlines.swift -o /tmp/newlines && /tmp/newlines
// Results recorded in docs/text.md (macOS 27.0.1).
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
for s in ["x\ny", "x\r\ny", "x\n\ny", "x\u{2028}y", "x\ty", "\nx\n"] {
  NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
  let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 22)); tf.usesSingleLineMode = true; win.contentView = tf; win.makeFirstResponder(tf); spin()
  let ed = tf.currentEditor() as! NSTextView
  ed.paste(nil); spin(); print(s.debugDescription, "->", ed.string.debugDescription)
  ed.string = ""; ed.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0)); spin(); print("  insertText ->", ed.string.debugDescription)
}
let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 22)); win.contentView = tf; win.makeFirstResponder(tf); spin()
NSPasteboard.general.clearContents(); NSPasteboard.general.setString("x\ny", forType: .string)
let ed = tf.currentEditor() as! NSTextView; ed.paste(nil); spin(); print("default NSTextField paste ->", ed.string.debugDescription)
