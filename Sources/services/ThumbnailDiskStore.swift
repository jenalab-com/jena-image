// Sources/services/ThumbnailDiskStore.swift
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// 썸네일 디스크 캐시. 키에 경로 해시·mtime·크기·px가 들어 있어 원본이 바뀌면 키가 달라지고,
/// 옛 항목은 GC(접근시각 LRU)가 치운다. 어느 스레드에서 불러도 된다.
///
/// 락은 바이트 카운터와 플래그만 지킨다. 디코드·인코드·디렉터리 열거는 락 밖에서 하므로
/// 워커 여러 개가 디스크 계층에서 서로를 기다리지 않는다. GC는 `gcQueue`(utility, 직렬)에서만 돈다.
/// 내부 상태는 전부 락·직렬 큐로 지키므로 워커의 @Sendable 클로저에 넘겨도 안전하다(`@unchecked Sendable`).
final class ThumbnailDiskStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()  // _limitBytes·_usedBytes·gcScheduled·loggedWriteFailure 전용
    private let gcQueue = DispatchQueue(label: "com.jenalab.jenaimage.thumbnail-disk-gc", qos: .utility)
    private var _limitBytes: Int
    private var _usedBytes = 0
    private var gcScheduled = false
    private(set) var isAvailable = false
    private var loggedWriteFailure = false

    init(directory: URL, limitBytes: Int) {
        self.directory = directory
        self._limitBytes = limitBytes
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            isAvailable = true
        } catch {
            NSLog("ThumbnailDiskStore: 디렉터리 생성 실패 — 디스크 캐시 비활성: \(error)")
        }
    }

    var limitBytes: Int {
        get { lock.lock(); defer { lock.unlock() }; return _limitBytes }
        set {
            lock.lock(); _limitBytes = newValue; lock.unlock()
            scheduleCollectIfNeeded()  // 메인 스레드(설정 슬라이더)에서 불러도 기다리지 않는다
        }
    }

    var usedBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return _usedBytes
    }

    // MARK: - Key

    static func key(path: String, mtimeSec: Int, fileSize: Int, px: Int) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        let hash16 = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(hash16)_\(mtimeSec)_\(fileSize)_\(px)"
    }

    /// 새 URL 인스턴스로 읽는다 — 리소스 값 캐시가 워커 스레드에서 비워지지 않아 mtime 변경을 놓치기 때문(Task 0 참고).
    /// 비워진 iCloud 파일도 `fileSize`는 원본 크기를 돌려주므로 디스크 캐시 조회가 정상 동작한다.
    static func sourceStamp(of url: URL) -> (mtimeSec: Int, fileSize: Int)? {
        guard let rv = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = rv.contentModificationDate, let size = rv.fileSize else { return nil }
        return (Int(mtime.timeIntervalSince1970), size)
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(String(key.prefix(2))).appendingPathComponent(key + ".heic")
    }

    // MARK: - Lookup / Store

    /// 락 없이 실행된다. 같은 키를 두 워커가 동시에 조회해도 읽기만 하므로 안전하고,
    /// GC가 그 사이 파일을 지우면 디코드가 실패해 생성 경로로 넘어갈 뿐이다.
    func lookup(url: URL, minPx: Int, levels: [Int]) -> CGImage? {
        guard isAvailable, let stamp = Self.sourceStamp(of: url) else { return nil }
        for px in levels.sorted() where px >= minPx {
            let key = Self.key(path: url.path, mtimeSec: stamp.mtimeSec, fileSize: stamp.fileSize, px: px)
            let file = fileURL(forKey: key)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                removeFile(file)  // 깨진 항목은 지우고 생성 경로로
                continue
            }
            // 접근시각 = 파일 mtime. 별도 메타 없이 LRU를 만든다(스펙 §2.3).
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return img
        }
        return nil
    }

    /// 인코드는 락 밖. 같은 키의 동시 저장은 Provider가 요청을 합치므로 일어나지 않는다.
    func store(_ image: CGImage, url: URL, px: Int) {
        guard isAvailable, let stamp = Self.sourceStamp(of: url) else { return }
        let key = Self.key(path: url.path, mtimeSec: stamp.mtimeSec, fileSize: stamp.fileSize, px: px)
        let file = fileURL(forKey: key)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            lock.lock(); _usedBytes += size; lock.unlock()
            scheduleCollectIfNeeded()
        } catch {
            lock.lock()
            let firstTime = !loggedWriteFailure
            loggedWriteFailure = true
            lock.unlock()
            if firstTime { NSLog("ThumbnailDiskStore: 쓰기 실패 — 메모리 캐시만으로 계속: \(error)") }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// 디렉터리를 옆 이름으로 옮기고(즉시) 빈 디렉터리를 새로 만든다. 수만 개 파일의 실제 삭제는 GC 큐에서.
    /// 호출자(설정 창)는 바로 usedBytes == 0을 본다.
    func clear() {
        guard isAvailable else { return }
        let trash = directory.deletingLastPathComponent()
            .appendingPathComponent("thumbs-trash-\(UUID().uuidString)", isDirectory: true)
        lock.lock()
        let moved = (try? FileManager.default.moveItem(at: directory, to: trash)) != nil
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _usedBytes = 0
        lock.unlock()
        if moved {
            gcQueue.async { try? FileManager.default.removeItem(at: trash) }
        }
    }

    /// 디렉터리를 훑어 usedBytes를 실제 값으로 맞춘다(비정상 종료 보정). 느리므로 백그라운드에서 부른다.
    func recount() {
        let total = allEntries().reduce(0) { $0 + $1.size }
        lock.lock(); _usedBytes = total; lock.unlock()
        scheduleCollectIfNeeded()
    }

    // MARK: - GC (gcQueue에서만 실행)

    private struct Entry { let url: URL; let size: Int; let date: Date }

    private func allEntries() -> [Entry] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [Entry] = []
        for case let u as URL in e where u.pathExtension == "heic" {
            let rv = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            out.append(Entry(url: u, size: rv?.fileSize ?? 0, date: rv?.contentModificationDate ?? .distantPast))
        }
        return out
    }

    /// 한도를 넘었고 GC가 걸려 있지 않으면 한 번만 건다. 저장마다 호출돼도 디렉터리 열거는 GC 1회당 한 번이다.
    private func scheduleCollectIfNeeded() {
        lock.lock()
        let needed = _usedBytes > _limitBytes && !gcScheduled
        if needed { gcScheduled = true }
        lock.unlock()
        guard needed else { return }
        gcQueue.async { [weak self] in self?.collect() }
    }

    private func collect() {
        lock.lock()
        let limit = _limitBytes
        let over = _usedBytes > limit
        lock.unlock()
        if over {
            let target = Int(Double(limit) * 0.9)
            for entry in allEntries().sorted(by: { $0.date < $1.date }) {
                if usedBytes <= target { break }
                removeFile(entry.url, size: entry.size)
            }
        }
        lock.lock(); gcScheduled = false; lock.unlock()
        // 도는 동안 한도가 더 내려갔거나 저장이 이어졌으면 한 번 더 건다(그 사이 요청은 gcScheduled 때문에 무시됐다).
        scheduleCollectIfNeeded()
    }

    private func removeFile(_ url: URL, size: Int? = nil) {
        let s = size ?? ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if (try? FileManager.default.removeItem(at: url)) != nil {
            lock.lock(); _usedBytes = max(0, _usedBytes - s); lock.unlock()
        }
    }
}
