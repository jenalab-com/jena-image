import AppKit

/// 색 값 복사. NSPasteboard.general에 문자열 하나만 넣는다.
enum ColorClipboard {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
