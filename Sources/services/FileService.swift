import AppKit
import Foundation

// MARK: - Sort

/// 브라우저 정렬 기준
enum SortKey: String, CaseIterable {
    case name, date, size, kind
}

// MARK: - Error

enum FileServiceError: Error, LocalizedError {
    case folderNotReadable(URL)
    case fileNotFound(URL)
    case nameConflict(String)
    case invalidFileName(String)
    case permissionDenied(URL)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderNotReadable(let url):
            return "이 폴더에 접근할 수 없습니다: \(url.lastPathComponent)"
        case .fileNotFound(let url):
            return "파일을 찾을 수 없습니다: \(url.lastPathComponent)"
        case .nameConflict(let name):
            return "같은 이름의 파일이 이미 존재합니다: \(name)"
        case .invalidFileName(let reason):
            return "잘못된 파일 이름입니다: \(reason)"
        case .permissionDenied(let url):
            return "권한이 부족합니다: \(url.lastPathComponent)"
        case .operationFailed(let message):
            return message
        }
    }
}

// MARK: - Protocol

protocol FileServiceProtocol {
    func contentsOfFolder(at url: URL, sortKey: SortKey, ascending: Bool) -> Result<(folders: [URL], images: [URL]), FileServiceError>
    func moveFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError>
    func copyFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError>
    func duplicateFile(at url: URL) -> Result<URL, FileServiceError>
    func trashFile(at url: URL) -> Result<Void, FileServiceError>
    func renameFile(at url: URL, newName: String) -> Result<URL, FileServiceError>
    func createFolder(in parentURL: URL, name: String) -> Result<URL, FileServiceError>
    func fileExists(at url: URL) -> Bool
}

// MARK: - Implementation

final class FileService: FileServiceProtocol {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contentsOfFolder(at url: URL, sortKey: SortKey, ascending: Bool) -> Result<(folders: [URL], images: [URL]), FileServiceError> {
        guard fileManager.isReadableFile(atPath: url.path) else {
            return .failure(.folderNotReadable(url))
        }

        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
        ]

        // 정렬에 필요한 날짜·크기를 열거 시 함께 prefetch (정렬 비교 중 추가 디스크 접근 방지)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: options
        ) else {
            return .failure(.folderNotReadable(url))
        }

        var folders: [URL] = []
        var images: [URL] = []

        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                folders.append(item)
            } else if ImageFile.allSupportedExtensions.contains(item.pathExtension.lowercased()) {
                images.append(item)
            }
        }

        // 폴더는 항상 위(분리 반환), 폴더/이미지 각각 동일 기준으로 정렬
        return .success((
            folders: sortURLs(folders, by: sortKey, ascending: ascending),
            images: sortURLs(images, by: sortKey, ascending: ascending)
        ))
    }

    /// 정렬 기준 값을 한 번씩만 읽어 캐시한 뒤 정렬한다.
    /// 동률은 이름순으로 안정화하며, 내림차순은 결과를 뒤집는다.
    private func sortURLs(_ urls: [URL], by key: SortKey, ascending: Bool) -> [URL] {
        let byName: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        let result: [URL]
        switch key {
        case .name:
            result = urls.sorted(by: byName)
        case .kind:
            result = urls.sorted {
                let e0 = $0.pathExtension.lowercased(), e1 = $1.pathExtension.lowercased()
                if e0 != e1 { return e0.localizedStandardCompare(e1) == .orderedAscending }
                return byName($0, $1)
            }
        case .date:
            let dates: [URL: Date] = Dictionary(uniqueKeysWithValues: urls.map {
                ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            })
            result = urls.sorted {
                let d0 = dates[$0] ?? .distantPast, d1 = dates[$1] ?? .distantPast
                if d0 != d1 { return d0 < d1 }
                return byName($0, $1)
            }
        case .size:
            let sizes: [URL: Int] = Dictionary(uniqueKeysWithValues: urls.map {
                ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            })
            result = urls.sorted {
                let s0 = sizes[$0] ?? 0, s1 = sizes[$1] ?? 0
                if s0 != s1 { return s0 < s1 }
                return byName($0, $1)
            }
        }
        return ascending ? result : result.reversed()
    }

    func moveFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError> {
        let destination = destinationFolder.appendingPathComponent(source.lastPathComponent)

        if fileManager.fileExists(atPath: destination.path) {
            return .failure(.nameConflict(source.lastPathComponent))
        }

        do {
            try fileManager.moveItem(at: source, to: destination)
            return .success(destination)
        } catch {
            return .failure(.operationFailed("파일을 이동할 수 없습니다: \(error.localizedDescription)"))
        }
    }

    func copyFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError> {
        let destination = destinationFolder.appendingPathComponent(source.lastPathComponent)

        if fileManager.fileExists(atPath: destination.path) {
            return .failure(.nameConflict(source.lastPathComponent))
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
            return .success(destination)
        } catch {
            return .failure(.operationFailed("파일을 복사할 수 없습니다: \(error.localizedDescription)"))
        }
    }

    /// 같은 폴더에 사본을 만든다. 이름 충돌을 피해 "파일 2.ext" 식으로 번호를 붙인다.
    func duplicateFile(at url: URL) -> Result<URL, FileServiceError> {
        let folder = url.deletingLastPathComponent()
        let destination = folder.appendingPathComponent(uniqueName(for: url.lastPathComponent, in: folder))
        do {
            try fileManager.copyItem(at: url, to: destination)
            return .success(destination)
        } catch {
            return .failure(.operationFailed("파일을 복제할 수 없습니다: \(error.localizedDescription)"))
        }
    }

    /// 폴더 안에서 충돌하지 않는 이름을 만든다 ("이름 2.ext", "이름 3.ext" …).
    private func uniqueName(for name: String, in folder: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
                return candidate
            }
            counter += 1
        }
    }

    func trashFile(at url: URL) -> Result<Void, FileServiceError> {
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(.operationFailed("파일을 삭제할 수 없습니다: \(error.localizedDescription)"))
        }
    }

    func renameFile(at url: URL, newName: String) -> Result<URL, FileServiceError> {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)

        if trimmedName.isEmpty {
            return .failure(.invalidFileName("파일 이름이 비어있습니다"))
        }
        if trimmedName.contains("/") || trimmedName.contains(":") {
            return .failure(.invalidFileName("파일 이름에 '/' 또는 ':'를 사용할 수 없습니다"))
        }

        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmedName)

        if destination == url {
            return .success(url)
        }

        if fileManager.fileExists(atPath: destination.path) {
            return .failure(.nameConflict(trimmedName))
        }

        do {
            try fileManager.moveItem(at: url, to: destination)
            return .success(destination)
        } catch {
            return .failure(.operationFailed("파일 이름을 변경할 수 없습니다: \(error.localizedDescription)"))
        }
    }

    func createFolder(in parentURL: URL, name: String) -> Result<URL, FileServiceError> {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if trimmedName.isEmpty {
            return .failure(.invalidFileName("폴더 이름이 비어있습니다"))
        }
        if trimmedName.contains("/") || trimmedName.contains(":") {
            return .failure(.invalidFileName("폴더 이름에 '/' 또는 ':'를 사용할 수 없습니다"))
        }

        let newFolderURL = parentURL.appendingPathComponent(trimmedName)

        if fileManager.fileExists(atPath: newFolderURL.path) {
            return .failure(.nameConflict(trimmedName))
        }

        do {
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            return .success(newFolderURL)
        } catch {
            return .failure(.operationFailed("폴더를 생성할 수 없습니다: \(error.localizedDescription)"))
        }
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}
