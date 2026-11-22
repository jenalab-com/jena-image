import Foundation

/// 웹 패널 검색엔진. 주소 값은 jena-web `Resources/search-providers.json`과 같다.
enum WebSearchProvider: String, CaseIterable {
    case google, bing, naver

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .naver: return "네이버"
        }
    }

    func searchTemplate(for mode: WebSearchMode) -> String {
        switch (self, mode) {
        case (.google, .web): return "https://www.google.com/search"
        case (.google, .images): return "https://www.google.com/search?udm=2"
        case (.bing, .web): return "https://www.bing.com/search"
        case (.bing, .images): return "https://www.bing.com/images/search"
        case (.naver, .web): return "https://search.naver.com/search.naver"
        case (.naver, .images): return "https://search.naver.com/search.naver?where=image"
        }
    }

    /// 검색어를 싣는 키. 네이버만 `query`.
    var queryKey: String { self == .naver ? "query" : "q" }
}

enum WebSearchMode: String, CaseIterable { case web, images }

enum WebAddressError: LocalizedError, Equatable {
    case emptyInput, invalidAddress, unsupportedScheme

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "검색어나 주소를 입력해주세요."
        case .invalidAddress: return "주소를 확인해주세요."
        case .unsupportedScheme: return "HTTP 또는 HTTPS 주소를 입력해주세요."
        }
    }
}

/// 주소창 입력을 열 주소로 바꾼다. jena-web `NavigationService`·`SearchService`의 규칙을 옮겼다.
/// `://`가 있으면 http/https만, 공백 없이 점이 있으면 `https://`를 붙이고, 그 밖은 검색한다.
enum WebAddressResolver {
    static func resolve(_ input: String, provider: WebSearchProvider, mode: WebSearchMode) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw WebAddressError.emptyInput }
        let lower = text.lowercased()
        if ["javascript:", "data:", "file:", "mailto:", "tel:", "about:"].contains(where: lower.hasPrefix) {
            throw WebAddressError.unsupportedScheme
        }
        if text.contains("://") {
            guard let url = URL(string: text), let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()) else { throw WebAddressError.unsupportedScheme }
            guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw WebAddressError.invalidAddress
            }
            return url
        }
        if !text.contains(where: \.isWhitespace), text.contains("."),
           let url = URL(string: "https://" + text), let host = url.host, host.contains("."),
           url.user == nil, url.password == nil { return url }
        return try searchURL(query: text, provider: provider, mode: mode)
    }

    private static func searchURL(query: String, provider: WebSearchProvider, mode: WebSearchMode) throws -> URL {
        guard var parts = URLComponents(string: provider.searchTemplate(for: mode)) else {
            throw WebAddressError.invalidAddress
        }
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: provider.queryKey, value: query)]
        // URLComponents는 쿼리의 `+`를 그대로 두는데 검색엔진은 이를 공백으로 읽는다("c++" → "c  ").
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw WebAddressError.invalidAddress }
        return url
    }
}
