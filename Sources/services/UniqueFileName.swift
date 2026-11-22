import Foundation

enum UniqueFileName {
    /// 이름이 비어 있으면 그대로, 겹치면 "이름 2.ext", "이름 3.ext"…
    static func make(for name: String, in folder: URL, exists: (URL) -> Bool) -> String {
        guard !name.isEmpty, exists(folder.appendingPathComponent(name)) else { return name }
        let baseName = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            if !exists(folder.appendingPathComponent(candidate)) { return candidate }
            counter += 1
        }
    }
}
