import Foundation

/// 페이지 스크립트가 알린 `<img>` 정보. 메시지 모양은 `{kind, image: {currentSrc, src, srcset}, pageURL}`.
struct WebImageReport: Equatable {
    let currentSrc: String, src: String, srcset: String, pageURL: String

    init(currentSrc: String, src: String, srcset: String, pageURL: String) {
        self.currentSrc = currentSrc
        self.src = src
        self.srcset = srcset
        self.pageURL = pageURL
    }

    /// 스크립트가 보낸 `[String: Any]`. "image" 키가 없으면 nil.
    init?(message: Any) {
        guard let body = message as? [String: Any], let image = body["image"] as? [String: Any] else { return nil }
        self.init(currentSrc: image["currentSrc"] as? String ?? "",
                  src: image["src"] as? String ?? "",
                  srcset: image["srcset"] as? String ?? "",
                  pageURL: body["pageURL"] as? String ?? "")
    }
}

/// 저장할 이미지 주소와 파일 이름을 정하는 순수 로직.
enum WebImageCandidate {
    static let imageExtensions: Set<String> = Set(ImageFormat.allCases.flatMap { $0.fileExtensions })

    private static let savableSchemes: Set<String> = ["http", "https", "data"]

    /// `srcset`의 가장 큰 너비(`w`) 후보 → `currentSrc` → `src` 순으로, 저장할 수 있는 첫 주소.
    /// 상대 주소는 페이지 주소 기준으로 푼다. http·https·data만 받는다.
    static func bestURL(for report: WebImageReport) -> URL? {
        let base = URL(string: report.pageURL)
        let candidates = [widestSrcsetEntry(report.srcset), report.currentSrc, report.src].compactMap { $0 }
        for text in candidates {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), savableSchemes.contains(scheme) else { continue }
            if scheme != "data", url.host?.isEmpty ?? true { continue }
            return url
        }
        return nil
    }

    /// `srcset`에서 너비 서술자(`123w`)가 가장 큰 항목의 주소. 너비 후보가 없으면 nil.
    private static func widestSrcsetEntry(_ srcset: String) -> String? {
        var best: (url: String, width: Int)?
        for (url, descriptors) in srcsetCandidates(srcset) {
            guard let descriptor = descriptors.first(where: { $0.hasSuffix("w") }),
                  let width = Int(descriptor.dropLast()) else { continue }
            if width > (best?.width ?? -1) { best = (url, width) }
        }
        return best?.url
    }

    /// HTML 명세의 srcset 읽기를 줄인 것. 주소는 공백 없는 한 덩어리라 그 안의 쉼표(CDN 변환 주소·`data:`)는
    /// 주소의 일부다. 후보를 가르는 쉼표는 주소 끝에 붙은 것과 서술자 뒤(괄호 밖)에 오는 것뿐이다.
    private static func srcsetCandidates(_ srcset: String) -> [(url: String, descriptors: [String])] {
        let chars = Array(srcset)
        var result: [(url: String, descriptors: [String])] = []
        var i = 0
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace || chars[i] == "," { i += 1 }
            guard i < chars.count else { break }
            let urlStart = i
            while i < chars.count, !chars[i].isWhitespace { i += 1 }
            var url = String(chars[urlStart..<i])
            if url.hasSuffix(",") {
                while url.hasSuffix(",") { url.removeLast() }
                if !url.isEmpty { result.append((url, [])) }
                continue
            }
            var descriptorText = ""
            var depth = 0
            while i < chars.count {
                let c = chars[i]
                if c == "(" { depth += 1 } else if c == ")" { depth = max(0, depth - 1) }
                if c == ",", depth == 0 { i += 1; break }
                descriptorText.append(c)
                i += 1
            }
            result.append((url, descriptorText.split(whereSeparator: \.isWhitespace).map(String.init)))
        }
        return result
    }

    /// 서버가 제안한 이름 → 주소의 마지막 조각 → "웹 이미지 yyyy-MM-dd HH.mm.ss".
    /// 확장자가 없거나 이미지 확장자가 아니면 MIME으로 정한다.
    static func fileName(suggested: String?, url: URL, mimeType: String?, now: Date) -> String {
        let mimeExt = mimeType.flatMap(extensionForMIME)
        guard let name = sanitized(suggested) ?? urlName(url) else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let base = "웹 이미지 \(formatter.string(from: now))"
            return mimeExt.map { "\(base).\($0)" } ?? base
        }
        let ext = (name as NSString).pathExtension.lowercased()
        guard !imageExtensions.contains(ext), let mimeExt else { return name }
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        return "\(base).\(mimeExt)"
    }

    /// 경로를 떼어 낸 마지막 조각. 숨김 파일이 되지 않게 앞의 점을 뗀다. 쓸 게 없으면 nil.
    private static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let name = last.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "." })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func urlName(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return sanitized(url.lastPathComponent)
    }

    private static func extensionForMIME(_ mimeType: String) -> String? {
        let type = mimeType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard type.hasPrefix("image/") else { return nil }
        let subtype = String(type.dropFirst("image/".count))
        if subtype == "jpeg" { return "jpg" }
        return ["png", "gif", "webp", "avif", "bmp", "tiff", "heic", "heif"].contains(subtype) ? subtype : nil
    }

    /// `data:[MIME][;base64],본문`을 푼다. MIME이 없으면 `text/plain`.
    static func decodeDataURL(_ url: URL) -> (data: Data, mimeType: String)? {
        let text = url.absoluteString
        guard text.lowercased().hasPrefix("data:"), let comma = text.firstIndex(of: ",") else { return nil }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma].split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let payload = String(text[text.index(after: comma)...])
        let mimeType = header.first.flatMap { $0.contains("/") ? $0 : nil } ?? "text/plain"
        let data: Data?
        if header.contains("base64") {
            data = Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters)
        } else {
            data = (payload.removingPercentEncoding ?? payload).data(using: .utf8)
        }
        guard let data else { return nil }
        return (data, mimeType)
    }
}
