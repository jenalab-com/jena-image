import Foundation

enum AppUpdateInstallability: Equatable {
    case ready
    /// Gatekeeper가 격리 위치에서 실행 중(다운로드 폴더에서 바로 연 경우 등).
    case translocated
    /// DMG 같은 읽기 전용 볼륨에서 실행 중.
    case readOnlyVolume
    /// 앱이 든 폴더에 쓸 권한이 없다.
    case notWritable

    var guidance: String {
        switch self {
        case .ready: return ""
        case .translocated: return "앱이 macOS 격리 위치에서 실행 중이라 직접 교체할 수 없어요. 응용 프로그램 폴더로 옮긴 뒤 다시 시도하거나 다운로드 페이지에서 받아 주세요."
        case .readOnlyVolume: return "앱이 DMG 같은 읽기 전용 위치에서 실행 중이에요. 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요."
        case .notWritable: return "앱이 있는 폴더에 쓸 권한이 없어 직접 교체할 수 없어요. 다운로드 페이지에서 받아 설치해 주세요."
        }
    }
}

/// 내려받은 DMG에서 새 앱을 꺼내 현재 앱 옆에 준비하고, 앱 종료 후 교체하는 스크립트를 실행한다.
struct AppUpdateInstaller {
    static let stagingPrefix = ".JenaImage-update-"

    static func installability(of bundleURL: URL) -> AppUpdateInstallability {
        if bundleURL.path.contains("/AppTranslocation/") { return .translocated }
        if (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true { return .readOnlyVolume }
        let parent = bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else { return .notWritable }
        return .ready
    }

    /// DMG를 마운트해 번들 ID·버전을 확인한 뒤 `target`과 같은 폴더의 숨김 임시 폴더로 복사한다.
    /// 같은 볼륨에 두어야 교체가 이동(rename)으로 끝난다. 실패하면 임시 폴더와 마운트를 모두 정리한다.
    func stage(dmg: URL, expectedVersion: String, bundleIdentifier: String, target: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("JenaImage-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mountPoint) }
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path]) == 0 else {
            throw AppUpdateError.mountFailed
        }
        defer {
            if run("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint.path]) != 0 {
                _ = run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mountPoint.path])
            }
        }

        let items = (try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        guard let app = items.first(where: {
            $0.pathExtension == "app" && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }) else { throw AppUpdateError.invalidBundle("앱을 찾지 못했어요.") }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else {
            throw AppUpdateError.invalidBundle("다른 앱의 설치 파일이에요.")
        }
        guard let version = info["CFBundleShortVersionString"] as? String,
              AppVersion.components(version) == AppVersion.components(expectedVersion) else {
            throw AppUpdateError.invalidBundle("릴리스 버전과 앱 버전이 달라요.")
        }

        let staging = target.deletingLastPathComponent().appendingPathComponent(Self.stagingPrefix + UUID().uuidString)
        let staged = staging.appendingPathComponent(target.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            guard run("/usr/bin/ditto", [app.path, staged.path]) == 0 else { throw AppUpdateError.replaceFailed("새 앱을 복사하지 못했어요.") }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw (error as? AppUpdateError) ?? .replaceFailed("임시 폴더를 만들지 못했어요.")
        }
        // 앱이 직접 받은 파일이라 보통 격리 속성이 없지만, 남아 있으면 첫 실행 경고가 뜨므로 지운다.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    /// `pid`가 끝나기를 기다렸다가 `target`을 `staged`로 교체하고 `relaunch`를 실행한다.
    /// 새 앱을 옮기지 못하면 기존 앱을 되돌리고 그 앱으로 다시 실행한다.
    @discardableResult
    func launchReplacement(staged: URL, target: URL, waitingFor pid: Int32,
                           relaunch: [String]? = nil) throws -> Process {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("JenaImage-replace-\(UUID().uuidString).sh")
        try Self.replacementScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), staged.path, target.path] + (relaunch ?? ["/usr/bin/open", target.path])
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    static let replacementScript = """
    #!/bin/sh
    # 인자: <대기할 PID> <준비된 새 앱> <교체할 앱> <다시 실행할 명령...>
    pid="$1"; staged="$2"; target="$3"; shift 3
    rm -f "$0"
    staging="$(dirname "$staged")"
    i=0
    while kill -0 "$pid" 2>/dev/null; do
      i=$((i + 1))
      if [ "$i" -gt 600 ]; then   # 60초 안에 종료되지 않으면(종료 취소 등) 아무것도 바꾸지 않는다
        rm -rf "$staging"
        exit 4
      fi
      sleep 0.1
    done
    backup="$staging/previous.app"
    if ! mv "$target" "$backup"; then
      "$@"
      exit 2
    fi
    if mv "$staged" "$target"; then
      rm -rf "$staging"
      "$@"
      exit 0
    fi
    mv "$backup" "$target"
    rm -rf "$staging"
    "$@"
    exit 3
    """

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
