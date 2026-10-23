// NSTextView behaviour probe for docs/text.md. Run: swiftc undo.swift -o /tmp/undo && /tmp/undo
// Results recorded in docs/text.md (macOS 27.0.1).
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
func make(_ s: String) -> NSTextView {
  let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
  tv.allowsUndo = true
  win.contentView = tv
  win.makeFirstResponder(tv)
  tv.string = s
  tv.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
  spin()
  tv.undoManager?.removeAllActions()
  return tv
}
func show(_ label: String, _ tv: NSTextView) {
  let r = tv.selectedRange()
  print(label, "|", tv.string.debugDescription, "sel", r.location, r.length)
}
let nf = NSRange(location: NSNotFound, length: 0)
func steps(_ tv: NSTextView, _ fs: [() -> Void]) { for f in fs { f(); spin() } }
var tv = make("")
steps(tv, [{ tv.insertText("a", replacementRange: nf) }, { tv.insertText("b", replacementRange: nf) }, { tv.insertText("c", replacementRange: nf) }, { tv.undoManager?.undo() }]); show("type a b c, undo:", tv)
tv = make("abc"); steps(tv, [{ tv.deleteBackward(nil) }, { tv.deleteBackward(nil) }, { tv.undoManager?.undo() }]); show("abc, bs bs, undo:", tv)
tv = make(""); steps(tv, [{ tv.insertText("a", replacementRange: nf) }, { tv.insertText("b", replacementRange: nf) }, { tv.deleteBackward(nil) }, { tv.undoManager?.undo() }]); show("type a b, bs, undo:", tv)
tv = make(""); steps(tv, [{ tv.insertText("a", replacementRange: nf) }, { tv.insertText("b", replacementRange: nf) }, { tv.moveLeft(nil) }, { tv.insertText("x", replacementRange: nf) }, { tv.undoManager?.undo() }]); show("type a b, left, x, undo:", tv)
tv = make(""); steps(tv, [{ tv.insertText("a", replacementRange: nf) }, { tv.insertText("b", replacementRange: nf) }, { tv.moveLeft(nil) }, { tv.insertText("x", replacementRange: nf) }, { tv.undoManager?.undo() }, { tv.undoManager?.undo() }]); show("type a b, left, x, undo undo:", tv)
tv = make("hello"); steps(tv, [{ tv.setSelectedRange(NSRange(location: 1, length: 3)) }, { tv.cut(nil) }, { tv.undoManager?.undo() }]); show("cut ell, undo:", tv)
tv = make("abc"); steps(tv, [{ tv.selectAll(nil) }, { tv.insertText("x", replacementRange: nf) }, { tv.insertText("y", replacementRange: nf) }, { tv.undoManager?.undo() }]); show("selectAll, x, y, undo:", tv)
NSPasteboard.general.clearContents(); NSPasteboard.general.setString("Z", forType: .string)
tv = make("ab"); steps(tv, [{ tv.insertText("c", replacementRange: nf) }, { tv.paste(nil) }, { tv.insertText("d", replacementRange: nf) }, { tv.undoManager?.undo() }]); show("type c, paste Z, type d, undo:", tv)
tv = make("ab"); steps(tv, [{ tv.paste(nil) }, { tv.paste(nil) }, { tv.undoManager?.undo() }]); show("paste paste undo:", tv)
tv = make("ab"); steps(tv, [{ tv.setSelectedRange(NSRange(location: 1, length: 0)) }, { tv.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0), replacementRange: nf) }, { tv.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: nf) }, { tv.unmarkText() }, { tv.undoManager?.undo() }]); show("compose か, unmark, undo:", tv)
tv = make("ab"); steps(tv, [{ tv.insertText("x", replacementRange: nf) }, { tv.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0), replacementRange: nf) }, { tv.insertText("か", replacementRange: nf) }, { tv.undoManager?.undo() }]); show("type x, compose k, commit か, undo:", tv)
tv = make("ab"); steps(tv, [{ tv.insertText("x", replacementRange: nf) }, { tv.undoManager?.undo() }, {}]); show("type x undo:", tv); steps(tv, [{ tv.undoManager?.redo() }]); show(" redo:", tv)
tv = make("hello"); steps(tv, [{ tv.setSelectedRange(NSRange(location: 1, length: 3)) }, { tv.copy(nil) }]); print("copy:", NSPasteboard.general.string(forType: .string) ?? "nil")
tv = make("hello"); steps(tv, [{ tv.copy(nil) }]); print("copy with empty sel:", NSPasteboard.general.string(forType: .string) ?? "nil")
NSPasteboard.general.clearContents(); NSPasteboard.general.setString("x\ny", forType: .string)
let fe = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100)); fe.isFieldEditor = true; win.contentView = fe; win.makeFirstResponder(fe)
fe.paste(nil); spin(); print("field editor paste x\\ny:", fe.string.debugDescription)
let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 22)); tf.usesSingleLineMode = true; tf.cell?.usesSingleLineMode = true; win.contentView = tf; win.makeFirstResponder(tf); spin()
if let ed = tf.currentEditor() as? NSTextView { ed.paste(nil); spin(); print("NSTextField single-line paste x\\ny:", ed.string.debugDescription, tf.stringValue.debugDescription) } else { print("no editor") }
