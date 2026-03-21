import AppKit
import Foundation

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
    func contentsOfFolder(at url: URL) -> Result<(folders: [URL], images: [URL]), FileServiceError>
    func moveFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError>
    func copyFile(from source: URL, to destinationFolder: URL) -> Result<URL, FileServiceError>
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

    func contentsOfFolder(at url: URL) -> Result<(folders: [URL], images: [URL]), FileServiceError> {
        guard fileManager.isReadableFile(atPath: url.path) else {
            return .failure(.folderNotReadable(url))
        }

        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
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

        let sortedFolders = folders.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let sortedImages = images.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return .success((folders: sortedFolders, images: sortedImages))
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
