import Foundation

/// 지원 언어
enum Language: String, CaseIterable {
    case korean = "ko"
    case english = "en"
    case japanese = "ja"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        case .japanese: return "日本語"
        case .chinese: return "中文"
        }
    }
}

/// 다국어 문자열 키
enum L10nKey: String {
    // App
    case appName
    case about
    case preferences
    case hideApp
    case hideOthers
    case showAll
    case quit

    // File
    case file
    case addFolder
    case revealInFinder
    case rename
    case moveTo
    case copyTo
    case saveAs
    case delete

    // Edit
    case edit
    case copy
    case selectAll

    // Image
    case image
    case imageEdit

    // View
    case view
    case toggleSidebar
    case goBack
    case prevImage
    case nextImage
    case zoomIn
    case zoomOut
    case actualSize
    case fitToWindow

    // Window
    case window
    case minimize
    case zoom
    case fullScreen

    // Help
    case help
    case appHelp

    // Preferences
    case general
    case language
    case appearance
    case viewer
    case bgColor
    case bgColorDark
    case bgColorLight
    case bgColorSystem
    case defaultFormat
    case defaultQuality
    case restartRequired

    // Editor
    case editTools
    case crop
    case imageSize
    case canvasSize
    case apply
    case cancel
    case close
    case saveAsFile
    case undo
    case redo

    // Common
    case width
    case height
    case lockAspect
    case relative
    case absolute
    case alignment
    case background
    case transparent
    case result
    case confirm
    case continueAction
}

/// 다국어 문자열 관리
enum L10n {
    private static var currentLanguage: Language = {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"
        return Language(rawValue: saved) ?? .korean
    }()

    static var language: Language {
        get { currentLanguage }
        set {
            currentLanguage = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
        }
    }

    static func string(_ key: L10nKey) -> String {
        strings[currentLanguage]?[key] ?? strings[.korean]?[key] ?? key.rawValue
    }

    // MARK: - String Tables

    private static let strings: [Language: [L10nKey: String]] = [
        .korean: [
            .appName: "JenaImage",
            .about: "JenaImage에 대하여",
            .preferences: "설정…",
            .hideApp: "JenaImage 숨기기",
            .hideOthers: "기타 숨기기",
            .showAll: "모두 보기",
            .quit: "JenaImage 종료",
            .file: "파일",
            .addFolder: "폴더 추가…",
            .revealInFinder: "Finder에서 보기",
            .rename: "이름 변경",
            .moveTo: "이동…",
            .copyTo: "복사…",
            .saveAs: "다른 이름으로 저장…",
            .delete: "삭제",
            .edit: "편집",
            .copy: "복사",
            .selectAll: "모두 선택",
            .image: "이미지",
            .imageEdit: "이미지 편집…",
            .view: "보기",
            .toggleSidebar: "사이드바 보기/숨기기",
            .goBack: "뒤로",
            .prevImage: "이전 이미지",
            .nextImage: "다음 이미지",
            .zoomIn: "확대",
            .zoomOut: "축소",
            .actualSize: "원본 크기",
            .fitToWindow: "화면에 맞춤",
            .window: "윈도우",
            .minimize: "최소화",
            .zoom: "확대/축소",
            .fullScreen: "전체 화면 시작/종료",
            .help: "도움말",
            .appHelp: "JenaImage 도움말",
            .general: "일반",
            .language: "언어",
            .appearance: "화면",
            .viewer: "뷰어",
            .bgColor: "배경색",
            .bgColorDark: "어두운 배경",
            .bgColorLight: "밝은 배경",
            .bgColorSystem: "시스템 기본",
            .defaultFormat: "기본 내보내기 포맷",
            .defaultQuality: "기본 품질",
            .restartRequired: "언어 변경은 앱을 다시 시작해야 적용됩니다.",
            .editTools: "편집 도구",
            .crop: "자르기",
            .imageSize: "이미지 크기",
            .canvasSize: "캔버스 크기",
            .apply: "적용",
            .cancel: "취소",
            .close: "닫기",
            .saveAsFile: "다른 이름으로 저장",
            .undo: "실행 취소",
            .redo: "다시 실행",
            .width: "너비:",
            .height: "높이:",
            .lockAspect: "비율 유지",
            .relative: "상대",
            .absolute: "절대",
            .alignment: "정렬:",
            .background: "배경:",
            .transparent: "투명",
            .result: "결과:",
            .confirm: "확인",
            .continueAction: "계속",
        ],
        .english: [
            .appName: "JenaImage",
            .about: "About JenaImage",
            .preferences: "Settings…",
            .hideApp: "Hide JenaImage",
            .hideOthers: "Hide Others",
            .showAll: "Show All",
            .quit: "Quit JenaImage",
            .file: "File",
            .addFolder: "Add Folder…",
            .revealInFinder: "Reveal in Finder",
            .rename: "Rename",
            .moveTo: "Move To…",
            .copyTo: "Copy To…",
            .saveAs: "Save As…",
            .delete: "Delete",
            .edit: "Edit",
            .copy: "Copy",
            .selectAll: "Select All",
            .image: "Image",
            .imageEdit: "Edit Image…",
            .view: "View",
            .toggleSidebar: "Toggle Sidebar",
            .goBack: "Back",
            .prevImage: "Previous Image",
            .nextImage: "Next Image",
            .zoomIn: "Zoom In",
            .zoomOut: "Zoom Out",
            .actualSize: "Actual Size",
            .fitToWindow: "Fit to Window",
            .window: "Window",
            .minimize: "Minimize",
            .zoom: "Zoom",
            .fullScreen: "Toggle Full Screen",
            .help: "Help",
            .appHelp: "JenaImage Help",
            .general: "General",
            .language: "Language",
            .appearance: "Appearance",
            .viewer: "Viewer",
            .bgColor: "Background",
            .bgColorDark: "Dark",
            .bgColorLight: "Light",
            .bgColorSystem: "System Default",
            .defaultFormat: "Default Export Format",
            .defaultQuality: "Default Quality",
            .restartRequired: "Language change requires app restart.",
            .editTools: "Edit Tools",
            .crop: "Crop",
            .imageSize: "Image Size",
            .canvasSize: "Canvas Size",
            .apply: "Apply",
            .cancel: "Cancel",
            .close: "Close",
            .saveAsFile: "Save As",
            .undo: "Undo",
            .redo: "Redo",
            .width: "Width:",
            .height: "Height:",
            .lockAspect: "Lock Aspect Ratio",
            .relative: "Relative",
            .absolute: "Absolute",
            .alignment: "Align:",
            .background: "Fill:",
            .transparent: "Transparent",
            .result: "Result:",
            .confirm: "OK",
            .continueAction: "Continue",
        ],
        .japanese: [
            .appName: "JenaImage",
            .about: "JenaImageについて",
            .preferences: "設定…",
            .hideApp: "JenaImageを隠す",
            .hideOthers: "ほかを隠す",
            .showAll: "すべてを表示",
            .quit: "JenaImageを終了",
            .file: "ファイル",
            .addFolder: "フォルダを追加…",
            .revealInFinder: "Finderで表示",
            .rename: "名前を変更",
            .moveTo: "移動…",
            .copyTo: "コピー…",
            .saveAs: "別名で保存…",
            .delete: "削除",
            .edit: "編集",
            .copy: "コピー",
            .selectAll: "すべてを選択",
            .image: "イメージ",
            .imageEdit: "イメージを編集…",
            .view: "表示",
            .toggleSidebar: "サイドバーの表示/非表示",
            .goBack: "戻る",
            .prevImage: "前のイメージ",
            .nextImage: "次のイメージ",
            .zoomIn: "拡大",
            .zoomOut: "縮小",
            .actualSize: "原寸大",
            .fitToWindow: "ウインドウに合わせる",
            .window: "ウインドウ",
            .minimize: "最小化",
            .zoom: "拡大/縮小",
            .fullScreen: "フルスクリーンの開始/終了",
            .help: "ヘルプ",
            .appHelp: "JenaImage ヘルプ",
            .general: "一般",
            .language: "言語",
            .appearance: "外観",
            .viewer: "ビューア",
            .bgColor: "背景色",
            .bgColorDark: "ダーク",
            .bgColorLight: "ライト",
            .bgColorSystem: "システムデフォルト",
            .defaultFormat: "デフォルト書き出し形式",
            .defaultQuality: "デフォルト品質",
            .restartRequired: "言語の変更にはアプリの再起動が必要です。",
            .editTools: "編集ツール",
            .crop: "切り抜き",
            .imageSize: "イメージサイズ",
            .canvasSize: "キャンバスサイズ",
            .apply: "適用",
            .cancel: "キャンセル",
            .close: "閉じる",
            .saveAsFile: "別名で保存",
            .undo: "取り消す",
            .redo: "やり直す",
            .width: "幅:",
            .height: "高さ:",
            .lockAspect: "縦横比を固定",
            .relative: "相対",
            .absolute: "絶対",
            .alignment: "配置:",
            .background: "背景:",
            .transparent: "透明",
            .result: "結果:",
            .confirm: "OK",
            .continueAction: "続ける",
        ],
        .chinese: [
            .appName: "JenaImage",
            .about: "关于 JenaImage",
            .preferences: "设置…",
            .hideApp: "隐藏 JenaImage",
            .hideOthers: "隐藏其他",
            .showAll: "全部显示",
            .quit: "退出 JenaImage",
            .file: "文件",
            .addFolder: "添加文件夹…",
            .revealInFinder: "在 Finder 中显示",
            .rename: "重命名",
            .moveTo: "移动到…",
            .copyTo: "复制到…",
            .saveAs: "另存为…",
            .delete: "删除",
            .edit: "编辑",
            .copy: "复制",
            .selectAll: "全选",
            .image: "图像",
            .imageEdit: "编辑图像…",
            .view: "视图",
            .toggleSidebar: "显示/隐藏侧边栏",
            .goBack: "返回",
            .prevImage: "上一张",
            .nextImage: "下一张",
            .zoomIn: "放大",
            .zoomOut: "缩小",
            .actualSize: "实际大小",
            .fitToWindow: "适合窗口",
            .window: "窗口",
            .minimize: "最小化",
            .zoom: "缩放",
            .fullScreen: "进入/退出全屏",
            .help: "帮助",
            .appHelp: "JenaImage 帮助",
            .general: "通用",
            .language: "语言",
            .appearance: "外观",
            .viewer: "查看器",
            .bgColor: "背景色",
            .bgColorDark: "深色",
            .bgColorLight: "浅色",
            .bgColorSystem: "系统默认",
            .defaultFormat: "默认导出格式",
            .defaultQuality: "默认品质",
            .restartRequired: "语言更改需要重新启动应用。",
            .editTools: "编辑工具",
            .crop: "裁剪",
            .imageSize: "图像大小",
            .canvasSize: "画布大小",
            .apply: "应用",
            .cancel: "取消",
            .close: "关闭",
            .saveAsFile: "另存为",
            .undo: "撤销",
            .redo: "重做",
            .width: "宽度:",
            .height: "高度:",
            .lockAspect: "锁定比例",
            .relative: "相对",
            .absolute: "绝对",
            .alignment: "对齐:",
            .background: "背景:",
            .transparent: "透明",
            .result: "结果:",
            .confirm: "确定",
            .continueAction: "继续",
        ],
    ]
}
