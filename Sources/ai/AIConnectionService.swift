import Foundation
import Darwin

struct AIConnectionStatus: Equatable, Sendable {
    enum State: Sendable { case missing, signedOut, connected, failed }
    let state: State
    let executable: URL?
    let detail: String
    let account: String?

    static let missing = AIConnectionStatus(state: .missing, executable: nil,
        detail: "Codex CLI가 설치되어 있지 않습니다.", account: nil)
}

enum AIExecutableLocator {
    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        paths += ["\(home)/.local/bin", "\(home)/.cargo/bin", "\(home)/.npm-global/bin",
                  "\(home)/.volta/bin", "\(home)/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []
        paths += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(nvm)/\($0)/bin" }
        return paths.filter { $0.hasPrefix("/") }
    }

    static func resolve(_ path: String, directories: [String]? = nil) -> URL? {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        let candidates = expanded.contains("/") ? [expanded] : (directories ?? searchDirectories).map { $0 + "/" + expanded }
        return candidates.first { path in
            var directory: ObjCBool = false
            return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }.map { URL(fileURLWithPath: $0) }
    }

    static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([executable.deletingLastPathComponent().path] + searchDirectories).joined(separator: ":")
        return environment
    }
}

struct AIModelOption: Sendable, Equatable {
    let id: String
    let title: String
}

struct AIUsageWindow: Sendable, Equatable {
    let title: String
    let usedPercent: Double
    let resetsAt: Date?

    func summary(now: Date = Date()) -> String {
        let remaining: String
        if let resetsAt {
            let minutes = Int(ceil(max(0, resetsAt.timeIntervalSince(now)) / 60))
            remaining = minutes >= 1440
                ? "\(minutes / 1440)d \(minutes % 1440 / 60)h"
                : "\(minutes / 60)h \(minutes % 60)m"
        } else { remaining = "정보 없음" }
        return "\(title) · 사용 \(String(format: "%.0f", usedPercent))% · 리셋 \(remaining)"
    }

    static func parse(_ result: [String: Any]) -> [AIUsageWindow] {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let limits = buckets?.isEmpty == false ? buckets!
            : (result["rateLimits"] as? [String: Any]).map { ["codex": $0] } ?? [:]
        return limits.keys.sorted().flatMap { name -> [AIUsageWindow] in
            let bucket = limits[name]!
            return ["primary", "secondary"].compactMap { key in
                guard let row = bucket[key] as? [String: Any],
                      let percent = (row["usedPercent"] as? NSNumber)?.doubleValue,
                      percent.isFinite, percent >= 0 else { return nil }
                let minutes = row["windowDurationMins"] as? Int
                let period: String
                switch minutes {
                case 300: period = "5시간"
                case 10080: period = "주간"
                case 1440: period = "일간"
                case let value? where value > 0: period = value % 60 == 0 ? "\(value / 60)시간" : "\(value)분"
                default: period = key == "primary" ? "단기" : "장기"
                }
                let title = name == "codex" ? period : "\(bucket["limitName"] as? String ?? name) · \(period)"
                let timestamp = (row["resetsAt"] as? NSNumber)?.doubleValue
                let reset = timestamp.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                return AIUsageWindow(title: title, usedPercent: percent, resetsAt: reset)
            }
        }
    }
}

/// CLI 메타데이터만 조회한다. 인증 토큰을 저장하거나 생성 요청을 보내지 않는다.
final class AIConnectionService: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func check(path: String, timeout: TimeInterval = 20) async -> AIConnectionStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.inspect(path: path, timeout: timeout))
            }
        }
    }

    func usage(path: String, timeout: TimeInterval = 20) async throws -> [AIUsageWindow] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let executable = AIExecutableLocator.resolve(path) else {
                        throw AIImageGenerationError(message: "설정에서 CLI를 연결해 주세요.")
                    }
                    let result = try self.readResult(executable: executable, method: "account/rateLimits/read",
                                                     params: [:], timeout: timeout)
                    continuation.resume(returning: AIUsageWindow.parse(result))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func models(path: String, timeout: TimeInterval = 20) async throws -> [AIModelOption] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let executable = AIExecutableLocator.resolve(path) else {
                        throw AIImageGenerationError(message: "설정에서 CLI를 연결해 주세요.")
                    }
                    var models: [AIModelOption] = []
                    var cursors = Set<String>()
                    var cursor: String?
                    let deadline = Date().addingTimeInterval(timeout)
                    repeat {
                        var params: [String: Any] = ["limit": 100, "includeHidden": false]
                        if let cursor { params["cursor"] = cursor }
                        let result = try self.readResult(executable: executable, method: "model/list",
                                                         params: params, timeout: deadline.timeIntervalSinceNow)
                        guard let data = result["data"] as? [[String: Any]] else {
                            throw AIImageGenerationError(message: "CLI 모델 목록을 읽을 수 없습니다.")
                        }
                        for item in data {
                            guard let id = item["model"] as? String, !id.isEmpty,
                                  item["hidden"] as? Bool != true,
                                  (item["inputModalities"] as? [String] ?? ["text", "image"]).contains("image"),
                                  !models.contains(where: { $0.id == id }) else { continue }
                            models.append(.init(id: id, title: item["displayName"] as? String ?? id))
                        }
                        cursor = result["nextCursor"] as? String
                        if let cursor, !cursors.insert(cursor).inserted || cursors.count > 20 {
                            throw AIImageGenerationError(message: "CLI 모델 목록의 페이지 응답을 확인해 주세요.")
                        }
                    } while cursor != nil
                    continuation.resume(returning: models)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func accountStatus(result: [String: Any], executable: URL) -> AIConnectionStatus {
        guard result.keys.contains("account") else {
            return .init(state: .failed, executable: executable, detail: "CLI 계정 응답 형식을 확인할 수 없습니다. CLI를 업데이트한 뒤 재확인해 주세요.", account: nil)
        }
        guard let account = result["account"] as? [String: Any] else {
            if result["requiresOpenaiAuth"] as? Bool == false {
                return .init(state: .connected, executable: executable,
                             detail: "인증 없이 사용하는 CLI 제공자가 설정되어 있습니다.", account: "사용자 지정 제공자 · 계정 정보 없음")
            }
            return .init(state: .signedOut, executable: executable, detail: "CLI가 설치되어 있습니다. 로그인해 주세요.", account: nil)
        }
        let type = account["type"] as? String ?? ""
        let identity: String
        if type == "chatgpt" {
            let email = account["email"] as? String ?? "이메일 미제공"
            let plan = account["planType"] as? String
            identity = "ChatGPT · " + email + (plan.map { " · " + $0 } ?? "")
        } else if type == "apiKey" {
            identity = "API 키 연결 · 계정 이메일 미제공"
        } else {
            identity = "\(type.isEmpty ? "CLI" : type) · 계정 이메일 미제공"
        }
        return .init(state: .connected, executable: executable, detail: "CLI 연결 및 로그인 확인 완료", account: identity)
    }

    private func inspect(path: String, timeout: TimeInterval) -> AIConnectionStatus {
        guard let executable = AIExecutableLocator.resolve(path) else { return .missing }
        do {
            let result = try readResult(executable: executable, method: "account/read", params: ["refreshToken": true], timeout: timeout)
            return Self.accountStatus(result: result, executable: executable)
        } catch {
            return .init(state: .failed, executable: executable, detail: error.localizedDescription, account: nil)
        }
    }

    private func readResult(executable: URL, method: String, params: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JenaImage-Connection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("response")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: outputURL)
        let reader = try FileHandle(forReadingFrom: outputURL)
        defer { try? reader.close(); try? output.close() }
        let input = Pipe()
        defer { try? input.fileHandleForWriting.close() }
        // A CLI exiting early must produce an error, not terminate the GUI with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.environment = AIExecutableLocator.environment(for: executable)
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard !isCancelled else { throw AIImageGenerationError(message: "연결 확인을 취소했습니다.") }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(0.3)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }
        func send(_ object: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: object)
            bytes.append(10)
            try input.fileHandleForWriting.write(contentsOf: bytes)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "jena_image", "title": "JenaImage", "version": "2.0.0"],
            "capabilities": ["experimentalApi": false]
        ]])
        var buffer = Data()
        var initialized = false
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isCancelled { throw AIImageGenerationError(message: "연결 확인을 취소했습니다.") }
            let wasRunning = process.isRunning
            buffer.append(try reader.read(upToCount: 65536) ?? Data())
            guard buffer.count < 1_048_576 else { throw AIImageGenerationError(message: "CLI 응답이 너무 큽니다.") }
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end)
                buffer.removeSubrange(...end)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = message["id"] as? Int, id == 1 || id == 2 else { continue }
                if message["error"] != nil {
                    throw AIImageGenerationError(message: "CLI 정보 조회에 실패했습니다. 로그인 상태와 CLI 버전을 확인한 뒤 재확인해 주세요.")
                }
                if id == 1 && !initialized {
                    initialized = true
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": method, "params": params])
                } else if id == 2, let result = message["result"] as? [String: Any] {
                    return result
                }
            }
            if !wasRunning { throw AIImageGenerationError(message: "CLI가 요청한 정보를 반환하지 않고 종료되었습니다.") }
            Thread.sleep(forTimeInterval: 0.03)
        }
        throw AIImageGenerationError(message: "CLI 연결 확인 시간이 초과되었습니다. 재확인해 주세요.")
    }
}
