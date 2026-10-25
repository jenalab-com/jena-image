import Foundation

/// 원본의 위치와 무관한 이미지 모음. 파일이 없어져도 경로를 보존한다.
struct ImageCategory: Codable, Equatable {
    let id: UUID
    var name: String
    var paths: [String]

    var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }
}
