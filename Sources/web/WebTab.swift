import AppKit
import WebKit

/// 탭 줄에 보이는 탭 한 장의 값.
struct WebTabInfo: Equatable {
    let id: Int
    /// 페이지 제목. 없으면 주소의 호스트, 주소도 없으면 "새 탭".
    let title: String
    /// 지금 주소. 복원해 두고 아직 불러오지 않은 탭이면 그 주소, 빈 탭이면 빈 문자열.
    let address: String
    let isLoading: Bool
}

/// 웹 패널의 탭 한 장. 웹 뷰와 탭마다 따로 세는 상태(대화창 홍수 기록·소리 멈춤·미뤄 둔 주소)를 갖는다.
/// 탭이 닫히면 이 객체와 함께 상태가 사라진다.
@MainActor
final class WebTab {
    let id: Int
    let view: WebPageView
    /// 이 탭을 새 창으로 연 탭. 이 탭이 고른 채로 닫히면 그 탭으로 돌아간다.
    let openerID: Int?
    /// 복원했지만 아직 불러오지 않은 주소. 탭을 처음 고를 때 불러온다.
    var pendingURL: URL?
    /// 다시 켤 때 열 주소. 불러오기를 마친 http/https 주소만 바꾼다(오류 페이지 주소도 그대로 둔다).
    var savedAddress: String
    var observations: [NSKeyValueObservation] = []
    /// 대화창 폭주 막기: 최근 대화창 시각과, 다음 페이지까지 자동으로 답할지.
    var dialogTimes: [Date] = []
    var dialogsSilenced = false
    /// `setAllMediaPlaybackSuspended`로 소리·영상을 멈춰 둔 상태.
    var mediaSuspended = false
    /// 이 탭의 페이지가 최근 1초 안에 새 탭을 연 시각과, 그 묶음에서 막았다고 이미 알렸는지.
    var openTimes: [Date] = []
    var openLimitNoticed = false
    /// 페이지 프로세스가 끝났다. 다음에 고를 때 다시 불러온다.
    var needsReload = false

    init(id: Int, view: WebPageView, openerID: Int?, pendingURL: URL?) {
        self.id = id
        self.view = view
        self.openerID = openerID
        self.pendingURL = pendingURL
        savedAddress = pendingURL?.absoluteString ?? ""
    }

    var info: WebTabInfo {
        let url = view.url ?? pendingURL
        let pageTitle = view.title ?? ""
        let host = url?.host ?? ""
        let title = !pageTitle.isEmpty ? pageTitle : (!host.isEmpty ? host : "새 탭")
        return WebTabInfo(id: id, title: title, address: url?.absoluteString ?? "", isLoading: view.isLoading)
    }
}

/// 우클릭 메뉴에 저장 항목을 붙이는 웹 뷰.
final class WebPageView: WKWebView {
    weak var engine: WebPageEngine?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        engine?.decorate(menu)
    }
}
