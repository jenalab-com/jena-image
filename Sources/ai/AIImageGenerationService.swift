import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers

enum AIImageProvider: String, CaseIterable, Sendable {
    case codex = "Codex CLI"
    case custom = "사용자 지정 CLI"
}

struct AIImageRequest: Sendable {
    let provider: AIImageProvider
    let executable: String
    let prompt: String
    let references: [URL]
    let destination: URL
    var history: String = ""
    var model: String = ""
}

struct AIImageGenerationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Each instance owns one job. Only explicit user cancellation terminates its CLI.
// Mutable process state is protected by lock across cancellation and execution.
final class AIImageGenerationService: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    static func resolveExecutable(_ path: String) throws -> URL {
        guard let executable = AIExecutableLocator.resolve(path) else {
            throw AIImageGenerationError(message: "CLI 실행 파일을 찾을 수 없습니다. 설정의 AI 연결을 확인하세요.")
        }
        return executable
    }

    static func arguments(for request: AIImageRequest, workspace: URL, references: [URL]) -> [String] {
        if request.provider == .custom { return [workspace.appendingPathComponent("request.json").path] }
        var arguments = ["exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--color", "never", "-C", workspace.path]
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        for reference in references { arguments += ["--image", reference.path] }
        arguments += ["--", """
        Generate an image using your available image-generation tool, using the attached references if any.
        Save only final generated images as PNG files directly inside ./output/.
        Do not modify reference files. Do not substitute SVG, code-drawn images, or copies of references.
        If image generation is unavailable, explain the missing capability and stop without creating output.
        Previous conversation (context only):
        \(request.history)
        User image prompt:
        \(request.prompt)
        """]
        return arguments
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }

    private func checkCancellation() throws {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { throw AIImageGenerationError(message: "생성을 취소했습니다. 작업 파일은 보존됩니다.") }
    }

    func generate(_ request: AIImageRequest) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try self.run(request)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func run(_ request: AIImageRequest) throws -> [URL] {
        let fileManager = FileManager.default
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIImageGenerationError(message: "생성할 이미지의 설명을 입력하세요.")
        }
        let executable = try Self.resolveExecutable(request.executable)
        let values = try request.destination.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true, fileManager.isWritableFile(atPath: request.destination.path) else {
            throw AIImageGenerationError(message: "저장 폴더에 쓸 수 없습니다. 다른 폴더를 선택하세요.")
        }
        try checkCancellation()
        let workspace = fileManager.temporaryDirectory.appendingPathComponent("JenaImage-AI-\(UUID().uuidString)")
        let output = workspace.appendingPathComponent("output")
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            let references = try request.references.enumerated().map { index, original -> URL in
                try checkCancellation()
                guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw AIImageGenerationError(message: "참조 이미지를 읽을 수 없습니다: \(original.lastPathComponent)")
                }
                let copy = workspace.appendingPathComponent("reference-\(index + 1).png")
                guard let target = CGImageDestinationCreateWithURL(copy as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw AIImageGenerationError(message: "참조 이미지 복사본을 만들 수 없습니다.")
                }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let orientation = properties?[kCGImagePropertyOrientation] ?? 1
                CGImageDestinationAddImage(target, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
                guard CGImageDestinationFinalize(target) else { throw AIImageGenerationError(message: "참조 이미지 저장 실패") }
                return copy
            }
            let payload: [String: Any] = ["version": 1, "prompt": request.prompt,
                                          "reference_images": references.map(\.path), "output_directory": output.path]
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                .write(to: workspace.appendingPathComponent("request.json"), options: .withoutOverwriting)
            let logURL = workspace.appendingPathComponent("cli.log")
            fileManager.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            let child = Process()
            child.executableURL = executable
            child.arguments = Self.arguments(for: request, workspace: workspace, references: references)
            child.currentDirectoryURL = workspace
            child.environment = AIExecutableLocator.environment(for: executable)
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = log
            child.standardError = log
            lock.lock()
            if isCancelled { lock.unlock(); try checkCancellation() }
            else {
                do { try child.run(); process = child; lock.unlock() }
                catch { lock.unlock(); throw error }
            }
            var cancellationDeadline: Date?
            while child.isRunning {
                lock.lock()
                let cancelled = isCancelled
                lock.unlock()
                if cancelled {
                    if cancellationDeadline == nil { cancellationDeadline = Date().addingTimeInterval(2) }
                    if Date() >= cancellationDeadline! { kill(child.processIdentifier, SIGKILL) }
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            child.waitUntilExit()
            lock.lock()
            process = nil
            lock.unlock()
            try checkCancellation()
            guard child.terminationStatus == 0 else {
                throw AIImageGenerationError(message: "CLI가 실패했습니다 (종료 코드 \(child.terminationStatus)). 로그인·설정 및 cli.log를 확인하세요.")
            }
            let candidates = try fileManager.contentsOfDirectory(at: output, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                .filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.path < $1.path }
            guard !candidates.isEmpty else {
                throw AIImageGenerationError(message: "생성된 PNG 이미지가 없습니다. 연결된 CLI에 이미지 생성 도구가 있는지 확인하세요.")
            }
            // Validate the complete batch before saving any result.
            for candidate in candidates {
                let properties = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                      let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                      CGImageSourceGetType(source) as String? == UTType.png.identifier,
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    throw AIImageGenerationError(message: "유효한 PNG 이미지가 아닙니다: \(candidate.lastPathComponent)")
                }
            }
            try checkCancellation()
            var saved: [URL] = []
            do {
                for candidate in candidates {
                    let destination = request.destination.appendingPathComponent("AI-\(UUID().uuidString).png")
                    try fileManager.copyItem(at: candidate, to: destination)
                    saved.append(destination)
                }
            } catch {
                throw AIImageGenerationError(message: "\(saved.count)개 저장 후 오류가 발생했습니다. 저장된 파일은 유지됩니다. \(error.localizedDescription)")
            }
            return saved
        } catch {
            throw AIImageGenerationError(message: "\(error.localizedDescription)\n작업 기록: \(workspace.path)")
        }
    }
}
