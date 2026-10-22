import Foundation
import Network
import XCTest

/// Real Safari receives a local page; the suite needs no external HTTP service.
final class LoopbackArticleServer {
    private let queue = DispatchQueue(label: "RSSReaderUITests.loopback")
    private let listener: NWListener

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() throws -> URL {
        let ready = XCTestExpectation(description: "Loopback HTTP listener ready")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.fulfill()
            default: break
            }
        }
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                guard data != nil else { connection.cancel(); return }
                let html = "<!doctype html><html><head><title>UI Smoke Source</title></head><body><h1>Local source article</h1></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let port = listener.port else {
            listener.cancel()
            throw ServerError.notReady
        }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/article")!
    }

    func stop() { listener.cancel() }
    private enum ServerError: Error { case notReady }
}
