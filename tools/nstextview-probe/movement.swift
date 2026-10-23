// NSTextView behaviour probe for docs/text.md. Run: swiftc movement.swift -o /tmp/movement && /tmp/movement
// Results recorded in docs/text.md (macOS 27.0.1).
import AppKit
let app = NSApplication.shared
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
func make(_ s: String) -> NSTextView {
  let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
  tv.allowsUndo = true
  win.contentView = tv
  win.makeFirstResponder(tv)
  tv.string = s
  tv.undoManager?.removeAllActions()
  tv.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
  return tv
}
func show(_ label: String, _ tv: NSTextView) {
  let r = tv.selectedRange()
  print(label, "|", tv.string.debugDescription, "sel", r.location, r.length)
}
var tv = make("hello")
tv.setSelectedRange(NSRange(location: 1, length: 3)); tv.moveWordLeft(nil); show("wordLeft from sel [1,4) in hello:", tv)
tv = make("one two three"); tv.setSelectedRange(NSRange(location: 4, length: 3)); tv.moveWordLeft(nil); show("wordLeft sel 'two':", tv)
tv = make("one two three"); tv.setSelectedRange(NSRange(location: 4, length: 3)); tv.moveWordRight(nil); show("wordRight sel 'two':", tv)
tv = make("one two three"); tv.setSelectedRange(NSRange(location: 4, length: 3)); tv.moveLeft(nil); show("left sel 'two':", tv)
tv = make("a👍🏽"); tv.deleteBackward(nil); show("deleteBackward a+thumbs+skin:", tv)
tv = make("e\u{301}"); tv.deleteBackward(nil); show("deleteBackward e+combining acute:", tv)
tv = make("a.b"); tv.moveWordLeft(nil); show("wordLeft a.b:", tv)
tv = make("hello big world  "); tv.deleteWordBackward(nil); show("deleteWordBackward 'hello big world  ':", tv)
tv = make("hello, world"); tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.deleteWordForward(nil); show("deleteWordForward from 0 'hello, world':", tv)
tv = make("café au lait"); tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.moveWordRight(nil); show("wordRight café:", tv)
tv = make("日本語のテキスト"); tv.moveWordLeft(nil); show("wordLeft japanese:", tv)
tv = make("don't stop"); tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.moveWordRight(nil); show("wordRight don't:", tv)
tv = make("foo_bar baz"); tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.moveWordRight(nil); show("wordRight foo_bar:", tv)
// Undo grouping needs the run loop to turn between steps; see undo.swift.
tv = make("hello"); tv.setSelectedRange(NSRange(location: 1, length: 3)); tv.moveLeft(nil); tv.moveRight(nil); show("sel [1,4) left right:", tv)
tv = make("abc"); tv.setSelectedRange(NSRange(location: 1, length: 0)); tv.moveRight(nil); tv.moveLeftAndModifySelection(nil); tv.moveLeftAndModifySelection(nil); show("caret 2, shift-left x2:", tv)
tv = make("abcdef"); tv.setSelectedRange(NSRange(location: 2, length: 2)); tv.moveRightAndModifySelection(nil); show("sel [2,4) shift-right:", tv)
tv = make("abcdef"); tv.setSelectedRange(NSRange(location: 2, length: 2)); tv.moveLeftAndModifySelection(nil); show("sel [2,4) shift-left:", tv)
// IME
tv = make("ab"); tv.setSelectedRange(NSRange(location: 1, length: 0));
tv.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); show("setMarked k:", tv); print(" marked", tv.markedRange())
tv.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); show("setMarked か:", tv); print(" marked", tv.markedRange())
tv.unmarkText(); show("unmark:", tv); print(" marked", tv.markedRange())
tv = make("ab"); tv.setSelectedRange(NSRange(location: 1, length: 0));
tv.setMarkedText("にほ", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0)); show("setMarked にほ sel(0,2):", tv)
tv.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0)); show("insert 日本 commits:", tv); print(" marked", tv.markedRange())
tv = make("a"); tv.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); tv.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); show("setMarked k then empty:", tv); print(" marked", tv.markedRange(), tv.hasMarkedText())
// field editor and newlines
let fe = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100)); fe.isFieldEditor = true; win.contentView = fe; win.makeFirstResponder(fe)
fe.insertText("a\nb", replacementRange: NSRange(location: NSNotFound, length: 0)); print("field editor insertText a\\nb:", fe.string.debugDescription)
