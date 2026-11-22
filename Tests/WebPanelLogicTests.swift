import Foundation

func runWebPanelLogicTests() {
    runTest("주소창 입력을 주소와 검색으로 가른다") {
        let r = { try? WebAddressResolver.resolve($0, provider: .google, mode: .images) }
        checkEqual(r("https://a.com/x")?.absoluteString, "https://a.com/x", "완전한 주소")
        checkEqual(r("pinterest.com")?.absoluteString, "https://pinterest.com", "점이 있으면 https")
        checkEqual(r("  노을 사진 ")?.absoluteString, "https://www.google.com/search?udm=2&q=%EB%85%B8%EC%9D%84%20%EC%82%AC%EC%A7%84", "검색")
        checkEqual(try? WebAddressResolver.resolve("고양이", provider: .naver, mode: .web).query, "query=%EA%B3%A0%EC%96%91%EC%9D%B4", "네이버 키")
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "ftp://a.com", "data:text/html,x"] {
            check((try? WebAddressResolver.resolve(bad, provider: .google, mode: .web)) == nil, "거부: \(bad)")
        }
        check((try? WebAddressResolver.resolve("https://user:pw@a.com", provider: .google, mode: .web)) == nil, "계정 정보가 든 주소 거부")
        check((try? WebAddressResolver.resolve("   ", provider: .google, mode: .web)) == nil, "빈 입력")
    }
    runTest("검색 제공자마다 정해진 주소와 검색어 키를 쓴다") {
        func url(_ p: WebSearchProvider, _ m: WebSearchMode) -> String? {
            (try? WebAddressResolver.resolve("a", provider: p, mode: m))?.absoluteString
        }
        checkEqual(url(.google, .web), "https://www.google.com/search?q=a", "Google 웹")
        checkEqual(url(.bing, .web), "https://www.bing.com/search?q=a", "Bing 웹")
        checkEqual(url(.bing, .images), "https://www.bing.com/images/search?q=a", "Bing 이미지")
        checkEqual(url(.naver, .images), "https://search.naver.com/search.naver?where=image&query=a", "네이버 이미지")
        checkEqual((try? WebAddressResolver.resolve("c++", provider: .google, mode: .web))?.query, "q=c%2B%2B", "검색어의 +는 공백이 되지 않게")
        checkEqual(WebSearchProvider.allCases.map(\.displayName), ["Google", "Bing", "네이버"], "표시 이름")
    }
    runTest("거부 사유를 오류 종류로 구분한다") {
        func error(_ s: String) -> WebAddressError? {
            do { _ = try WebAddressResolver.resolve(s, provider: .google, mode: .web); return nil }
            catch { return error as? WebAddressError }
        }
        checkEqual(error(" "), .emptyInput, "빈 입력")
        checkEqual(error("javascript:alert(1)"), .unsupportedScheme, "javascript")
        checkEqual(error("ftp://a.com"), .unsupportedScheme, "ftp")
        checkEqual(error("https://user:pw@a.com"), .invalidAddress, "계정 정보")
    }
    runTest("저장할 이미지 주소를 고른다") {
        let page = "https://site.com/board/1"
        func best(_ c: String, _ s: String, _ set: String) -> String? {
            WebImageCandidate.bestURL(for: WebImageReport(currentSrc: c, src: s, srcset: set, pageURL: page))?.absoluteString
        }
        checkEqual(best("https://i.com/236.jpg", "https://i.com/236.jpg", "https://i.com/236.jpg 236w, /orig.jpg 1200w, https://i.com/564.jpg 564w"), "https://site.com/orig.jpg", "srcset의 가장 큰 너비, 상대 주소 풀기")
        checkEqual(best("https://i.com/a.jpg", "", "https://i.com/a.jpg 1x, https://i.com/b.jpg 2x"), "https://i.com/a.jpg", "너비 후보가 없으면 currentSrc")
        checkEqual(best("", "img/a.png", ""), "https://site.com/board/img/a.png", "src만 있을 때")
        checkEqual(best("", "", "깨진, , 값"), nil, "쓸 주소가 없으면 nil")
        checkEqual(best("blob:https://site.com/1", "", ""), nil, "blob은 저장하지 않는다")
        check(best("data:image/png;base64,AAAA", "", "") != nil, "data는 허용")
    }
    runTest("쉼표가 든 srcset 주소를 통째로 읽는다") {
        let page = "https://site.com/board/1"
        func best(_ c: String, _ set: String) -> String? {
            WebImageCandidate.bestURL(for: WebImageReport(currentSrc: c, src: "", srcset: set, pageURL: page))?.absoluteString
        }
        let cdn = "https://res.cloudinary.com/x/image/upload"
        checkEqual(best("https://i.com/cur.jpg", "\(cdn)/w_300,h_200/a.jpg 300w, \(cdn)/w_100,h_50/a.jpg 100w"),
                   "\(cdn)/w_300,h_200/a.jpg", "쉼표가 든 주소에서 가장 큰 너비")
        checkEqual(best("https://i.com/cur.jpg", "\(cdn)/w_100,h_50/a.jpg 100w,\(cdn)/w_900,h_600/a.jpg 900w"),
                   "\(cdn)/w_900,h_600/a.jpg", "쉼표 뒤 공백 없이 이어진 후보")
        checkEqual(best("https://i.com/cur.jpg", "data:image/gif;base64,R0lGODlhAQABAAAAACw= 1w, https://i.com/big.jpg 800w, https://i.com/s.jpg 200w"),
                   "https://i.com/big.jpg", "data 자리표시 옆의 진짜 후보")
        checkEqual(best("https://i.com/cur.jpg", "data:image/gif;base64,R0lGODlhAQABAAAAACw= 1w"),
                   "data:image/gif;base64,R0lGODlhAQABAAAAACw=", "data 후보는 통째로")
        checkEqual(best("https://i.com/cur.jpg", "https://i.com/a.jpg,https://i.com/b.jpg 2x"),
                   "https://i.com/cur.jpg", "서술자 없는 후보와 x 후보만 있으면 currentSrc")
    }
    runTest("스크립트 메시지에서 이미지 보고를 읽는다") {
        let message: [String: Any] = ["image": ["currentSrc": "https://i.com/a.jpg", "src": "/a.jpg", "srcset": ""], "pageURL": "https://site.com/"]
        checkEqual(WebImageReport(message: message),
                   WebImageReport(currentSrc: "https://i.com/a.jpg", src: "/a.jpg", srcset: "", pageURL: "https://site.com/"),
                   "필드를 읽는다")
        check(WebImageReport(message: ["pageURL": "https://site.com/"]) == nil, "image 키가 없으면 nil")
        check(WebImageReport(message: "문자열") == nil, "사전이 아니면 nil")
    }
    runTest("파일 이름을 정한다") {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let u = URL(string: "https://i.com/p/sunset.jpg?w=1")!
        checkEqual(WebImageCandidate.fileName(suggested: "photo.png", url: u, mimeType: "image/png", now: now), "photo.png", "서버 제안")
        checkEqual(WebImageCandidate.fileName(suggested: nil, url: u, mimeType: "image/jpeg", now: now), "sunset.jpg", "주소의 마지막 조각")
        checkEqual(WebImageCandidate.fileName(suggested: "../../evil.png", url: u, mimeType: nil, now: now), "evil.png", "경로 제거")
        checkEqual(WebImageCandidate.fileName(suggested: "a/b.png", url: u, mimeType: nil, now: now), "b.png", "경로 제거")
        checkEqual(WebImageCandidate.fileName(suggested: nil, url: URL(string: "https://i.com/img?id=7")!, mimeType: "image/webp", now: now), "img.webp", "확장자를 MIME으로")
        checkEqual(WebImageCandidate.fileName(suggested: "view.php", url: u, mimeType: "image/jpeg", now: now), "view.jpg", "이미지 확장자가 아니면 MIME으로 바꿈")
        check(WebImageCandidate.fileName(suggested: nil, url: URL(string: "https://i.com/")!, mimeType: "image/png", now: now).hasPrefix("웹 이미지 "), "이름이 없으면 날짜 이름")
        let data = WebImageCandidate.decodeDataURL(URL(string: "data:image/png;base64,iVBORw0KGgo=")!)
        checkEqual(data?.mimeType, "image/png", "data 주소 MIME"); checkEqual(data?.data.count, 8, "data 주소 본문")
    }
    runTest("겹치는 이름에 번호를 붙인다") {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let taken: Set<String> = ["a.png", "a 2.png"]
        checkEqual(UniqueFileName.make(for: "a.png", in: folder) { taken.contains($0.lastPathComponent) }, "a 3.png", "다음 번호")
        checkEqual(UniqueFileName.make(for: "b.png", in: folder) { _ in false }, "b.png", "안 겹치면 그대로")
        checkEqual(UniqueFileName.make(for: "memo", in: folder) { $0.lastPathComponent == "memo" }, "memo 2", "확장자 없는 이름")
        checkEqual(UniqueFileName.make(for: "", in: folder) { _ in true }, "", "빈 이름은 그대로")
    }
}
