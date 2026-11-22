import Foundation
import Network

/// 테스트 전용. 127.0.0.1의 빈 포트에서 경로별 응답을 주고 받은 요청 헤더를 기록한다.
/// 요청 한 건마다 응답하고 연결을 닫는다.
final class WebTestServer: @unchecked Sendable {
    typealias Route = (status: Int, headers: [String: String], body: Data)

    private let routes: [String: Route]
    private let listener: NWListener
    private let queue = DispatchQueue(label: "jena.web-test-server")
    private let lock = NSLock()
    private var recorded: [String: [String: String]] = [:]
    private var delays: [String: (seconds: TimeInterval, leadingBytes: Int)] = [:]
    private(set) var baseURL: URL

    init(routes: [String: Route]) throws {
        self.routes = routes
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        baseURL = URL(string: "http://127.0.0.1")!
        let ready = DispatchSemaphore(value: 0)
        var failure: NWError?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, failure == nil, let port = listener.port else {
            listener.cancel()
            throw failure ?? NWError.posix(.ETIMEDOUT)
        }
        baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)")!
    }

    /// 그 경로로 마지막에 받은 요청의 헤더.
    func headers(forPath path: String) -> [String: String]? {
        lock.lock(); defer { lock.unlock() }
        return recorded[path]
    }

    func stop() { listener.cancel() }

    /// 그 경로의 본문을 머리말보다 늦게 보낸다(내려받기 겹침 재현용).
    /// `leadingBytes`만큼은 머리말과 함께 바로 보낸다(쓰는 도중의 내려받기 재현용).
    func delayBody(forPath path: String, by seconds: TimeInterval, leadingBytes: Int = 0) {
        lock.lock(); delays[path] = (seconds, leadingBytes); lock.unlock()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(to: buffer.subdata(in: buffer.startIndex..<end.lowerBound), on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: Data, on connection: NWConnection) {
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
        let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        lock.lock(); recorded[path] = headers; lock.unlock()

        let route = routes[path] ?? (404, ["Content-Type": "text/plain"], Data("not found".utf8))
        var response = "HTTP/1.1 \(route.status) \(HTTPURLResponse.localizedString(forStatusCode: route.status))\r\n"
        for (name, value) in route.headers { response += "\(name): \(value)\r\n" }
        response += "Content-Length: \(route.body.count)\r\nConnection: close\r\n\r\n"
        lock.lock(); let delay = delays[path] ?? (0, 0); lock.unlock()
        let split = min(delay.leadingBytes, route.body.count)
        connection.send(content: Data(response.utf8) + route.body.prefix(split), completion: .contentProcessed { _ in })
        queue.asyncAfter(deadline: .now() + delay.seconds) {
            connection.send(content: route.body.dropFirst(split), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
