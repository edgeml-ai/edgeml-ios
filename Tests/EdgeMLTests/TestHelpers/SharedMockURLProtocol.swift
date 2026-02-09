import Foundation

final class SharedMockURLProtocol: URLProtocol {
    enum MockResponse {
        case success(statusCode: Int, json: [String: Any])
        case failure(Error)
    }

    /// Host filter — when non-nil only intercept requests to this host.
    nonisolated(unsafe) static var allowedHost: String?
    nonisolated(unsafe) static var responses: [MockResponse] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        if let host = allowedHost {
            return request.url?.host == host
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            let bufferSize = 4096
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 { data.append(buffer, count: read) }
                else { break }
            }
            stream.close()
            captured.httpBody = data
        }
        Self.requests.append(captured)
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let next = Self.responses.removeFirst()
        switch next {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(statusCode: let statusCode, json: let json):
            do {
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}

    /// Resets all captured state. Call from `setUp()`.
    static func reset() {
        responses = []
        requests = []
        allowedHost = nil
    }
}
